"use strict";

const REQUIRED_LABELS = ["self-hosted", "macos", "unity-mobile"];
const FORBIDDEN_LABELS = ["ci", "unity-package-ci"];
const PROJECT_LABEL_PREFIX = "project-";
const MAX_LABEL_LENGTH = 100;

function labelNames(runner) {
    return (runner.labels || []).map((label) => String(label.name || "").toLowerCase());
}

function resolveAffinityLabel(configuredLabel, repositoryName) {
    const configured = String(configuredLabel || "").trim().toLowerCase();
    const repository = String(repositoryName || "").trim().toLowerCase();
    const slug = repository
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .replace(/-+/g, "-");
    const affinityLabel = configured || `${PROJECT_LABEL_PREFIX}${slug}`;

    if (!/^project-[a-z0-9]+(?:-[a-z0-9]+)*$/.test(affinityLabel)) {
        throw new Error(
            "UNITY_RUNNER_AFFINITY_LABEL must match project-<lowercase-slug>, " +
            "or the repository name must produce a non-empty lowercase slug."
        );
    }

    if (affinityLabel.length > MAX_LABEL_LENGTH) {
        throw new Error(`Affinity label exceeds ${MAX_LABEL_LENGTH} characters: ${affinityLabel.length}`);
    }

    return affinityLabel;
}

function hasRequiredPoolLabels(runner) {
    const labels = labelNames(runner);
    return REQUIRED_LABELS.every((label) => labels.includes(label)) &&
        FORBIDDEN_LABELS.every((label) => !labels.includes(label));
}

function projectLabelCount(runner) {
    return labelNames(runner).filter((label) => label.startsWith(PROJECT_LABEL_PREFIX)).length;
}

function stableHash(value) {
    let hash = 2166136261;
    for (const character of String(value)) {
        hash ^= character.charCodeAt(0);
        hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
}

function compareCandidates(left, right, affinityLabel) {
    const countDifference = projectLabelCount(left) - projectLabelCount(right);
    if (countDifference !== 0) return countDifference;

    const leftHash = stableHash(`${affinityLabel}:${left.id}`);
    const rightHash = stableHash(`${affinityLabel}:${right.id}`);
    if (leftHash !== rightHash) return leftHash - rightHash;

    return Number(left.id) - Number(right.id);
}

async function listOrganizationRunners(github, organization) {
    const runners = await github.paginate(
        github.rest.actions.listSelfHostedRunnersForOrg,
        { org: organization, per_page: 100 }
    );

    if (!Array.isArray(runners)) {
        throw new Error("GitHub runner API returned an unexpected response.");
    }

    return runners;
}

function validateExistingRunner(runner, affinityLabel) {
    if (!hasRequiredPoolLabels(runner)) {
        throw new Error(
            `Runner ${runner.name} already owns ${affinityLabel}, but it is outside the allowed unity-mobile pool.`
        );
    }

    if (String(runner.status).toLowerCase() !== "online") {
        throw new Error(
            `Runner ${runner.name} already owns ${affinityLabel}, but it is offline. ` +
            "The mobile build was not queued indefinitely."
        );
    }
}

async function removeAffinityLabel(github, organization, runnerId, affinityLabel) {
    try {
        await github.request(
            "DELETE /orgs/{org}/actions/runners/{runner_id}/labels/{name}",
            {
                org: organization,
                runner_id: runnerId,
                name: affinityLabel
            }
        );
    } catch (error) {
        if (Number(error.status) !== 404) throw error;
    }
}

async function reconcileConcurrentAssignments(github, organization, affinityLabel, mappedRunners, core) {
    if (mappedRunners.length <= 1) return mappedRunners;

    const sorted = [...mappedRunners].sort((left, right) =>
        compareCandidates(left, right, affinityLabel)
    );
    const winner = sorted[0];
    core.warning(
        `Concurrent ${affinityLabel} assignments were detected; keeping runner ${winner.name} and removing duplicates.`
    );

    for (const duplicate of sorted.slice(1)) {
        await removeAffinityLabel(github, organization, duplicate.id, affinityLabel);
    }

    return [winner];
}

async function allocate({ github, context, core, configuredLabel }) {
    const organization = context.repo.owner;
    const affinityLabel = resolveAffinityLabel(configuredLabel, context.repo.repo);
    let runners = await listOrganizationRunners(github, organization);
    let mappedRunners = runners.filter((runner) => labelNames(runner).includes(affinityLabel));

    if (mappedRunners.length > 1) {
        throw new Error(
            `Affinity label ${affinityLabel} is already assigned to multiple runners. ` +
            "Resolve the existing mapping before retrying."
        );
    }

    let selectedRunner;
    let mode;
    if (mappedRunners.length === 1) {
        selectedRunner = mappedRunners[0];
        validateExistingRunner(selectedRunner, affinityLabel);
        mode = "reused";
    } else {
        const candidates = runners
            .filter((runner) => String(runner.status).toLowerCase() === "online")
            .filter((runner) => runner.busy === false)
            .filter(hasRequiredPoolLabels)
            .sort((left, right) => compareCandidates(left, right, affinityLabel));

        if (candidates.length === 0) {
            throw new Error(
                "No online idle runner matches self-hosted, macOS, unity-mobile and excludes ci/unity-package-ci."
            );
        }

        selectedRunner = candidates[0];
        await github.request(
            "POST /orgs/{org}/actions/runners/{runner_id}/labels",
            {
                org: organization,
                runner_id: selectedRunner.id,
                labels: [affinityLabel]
            }
        );

        runners = await listOrganizationRunners(github, organization);
        mappedRunners = runners.filter((runner) => labelNames(runner).includes(affinityLabel));
        mappedRunners = await reconcileConcurrentAssignments(
            github,
            organization,
            affinityLabel,
            mappedRunners,
            core
        );

        if (mappedRunners.length !== 1) {
            throw new Error(`Failed to verify the ${affinityLabel} runner mapping after allocation.`);
        }

        selectedRunner = mappedRunners[0];
        validateExistingRunner(selectedRunner, affinityLabel);
        mode = "assigned";
    }

    core.setOutput("affinity_label", affinityLabel);
    core.setOutput("runner_id", String(selectedRunner.id));
    core.setOutput("runner_name", selectedRunner.name);
    core.setOutput("allocation_mode", mode);
    core.info(
        `${mode === "reused" ? "Reusing" : "Assigned"} ${affinityLabel} on runner ${selectedRunner.name}.`
    );

    return { affinityLabel, runner: selectedRunner, mode };
}

module.exports = {
    allocate,
    compareCandidates,
    hasRequiredPoolLabels,
    labelNames,
    projectLabelCount,
    resolveAffinityLabel,
    stableHash
};

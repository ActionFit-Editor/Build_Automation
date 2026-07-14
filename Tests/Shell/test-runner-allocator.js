"use strict";

const assert = require("assert");
const path = require("path");
const allocator = require(path.resolve(
    __dirname,
    "../../.github/scripts/allocate-unity-mobile-runner.js"
));

function runner(id, name, labels, { status = "online", busy = false } = {}) {
    return {
        id,
        name,
        status,
        busy,
        labels: labels.map((label) => ({ name: label }))
    };
}

function createFixture(initialRunners, afterPost) {
    let runners = initialRunners;
    const requests = [];
    const outputs = {};
    const github = {
        rest: {
            actions: {
                listSelfHostedRunnersForOrg: Symbol("listSelfHostedRunnersForOrg")
            }
        },
        paginate: async () => runners,
        request: async (route, parameters) => {
            requests.push({ route, parameters });
            if (route.startsWith("POST ")) {
                const target = runners.find((item) => item.id === parameters.runner_id);
                target.labels.push({ name: parameters.labels[0] });
                if (afterPost) runners = afterPost(runners, parameters);
                return {};
            }

            if (route.startsWith("DELETE ")) {
                const target = runners.find((item) => item.id === parameters.runner_id);
                target.labels = target.labels.filter(
                    (label) => label.name.toLowerCase() !== parameters.name.toLowerCase()
                );
                return {};
            }

            throw new Error(`Unexpected route: ${route}`);
        }
    };
    const core = {
        info: () => {},
        warning: () => {},
        setOutput: (name, value) => { outputs[name] = value; }
    };
    return { github, core, requests, outputs };
}

async function expectReject(promise, fragment) {
    await assert.rejects(promise, (error) => {
        assert.match(error.message, new RegExp(fragment));
        return true;
    });
}

async function run() {
    assert.strictEqual(
        allocator.resolveAffinityLabel("project-custom-game", "Ignored"),
        "project-custom-game"
    );
    assert.strictEqual(
        allocator.resolveAffinityLabel("", "AF_My Game"),
        "project-af-my-game"
    );
    assert.throws(
        () => allocator.resolveAffinityLabel("invalid", "game"),
        /must match/
    );

    const reusable = runner(
        10,
        "mobile-a",
        ["self-hosted", "macOS", "unity-mobile", "project-cat-merge-cafe"],
        { busy: true }
    );
    const reuseFixture = createFixture([reusable]);
    const reused = await allocator.allocate({
        github: reuseFixture.github,
        context: { repo: { owner: "ActionFitGames", repo: "Cat_Merge_Cafe" } },
        core: reuseFixture.core,
        configuredLabel: "project-cat-merge-cafe"
    });
    assert.strictEqual(reused.mode, "reused");
    assert.strictEqual(reuseFixture.requests.length, 0);
    assert.strictEqual(reuseFixture.outputs.runner_name, "mobile-a");

    const allocationFixture = createFixture([
        runner(1, "loaded", ["self-hosted", "macOS", "unity-mobile", "project-a", "project-b"]),
        runner(2, "selected", ["self-hosted", "macOS", "unity-mobile"]),
        runner(3, "ci-runner", ["self-hosted", "macOS", "unity-mobile", "ci"]),
        runner(4, "offline", ["self-hosted", "macOS", "unity-mobile"], { status: "offline" }),
        runner(5, "busy", ["self-hosted", "macOS", "unity-mobile"], { busy: true })
    ]);
    const assigned = await allocator.allocate({
        github: allocationFixture.github,
        context: { repo: { owner: "ActionFitGames", repo: "New_Game" } },
        core: allocationFixture.core,
        configuredLabel: ""
    });
    assert.strictEqual(assigned.mode, "assigned");
    assert.strictEqual(assigned.runner.id, 2);
    assert.strictEqual(allocationFixture.outputs.affinity_label, "project-new-game");
    assert.strictEqual(allocationFixture.requests[0].parameters.runner_id, 2);

    const offlineFixture = createFixture([
        runner(
            11,
            "offline-owner",
            ["self-hosted", "macOS", "unity-mobile", "project-cat-merge-cafe"],
            { status: "offline" }
        )
    ]);
    await expectReject(
        allocator.allocate({
            github: offlineFixture.github,
            context: { repo: { owner: "ActionFitGames", repo: "Cat_Merge_Cafe" } },
            core: offlineFixture.core,
            configuredLabel: "project-cat-merge-cafe"
        }),
        "offline"
    );

    const duplicateFixture = createFixture([
        runner(12, "duplicate-a", ["self-hosted", "macOS", "unity-mobile", "project-duplicate"]),
        runner(13, "duplicate-b", ["self-hosted", "macOS", "unity-mobile", "project-duplicate"])
    ]);
    await expectReject(
        allocator.allocate({
            github: duplicateFixture.github,
            context: { repo: { owner: "ActionFitGames", repo: "Duplicate" } },
            core: duplicateFixture.core,
            configuredLabel: "project-duplicate"
        }),
        "multiple runners"
    );

    const emptyFixture = createFixture([
        runner(14, "package-ci", ["self-hosted", "macOS", "unity-mobile", "unity-package-ci"])
    ]);
    await expectReject(
        allocator.allocate({
            github: emptyFixture.github,
            context: { repo: { owner: "ActionFitGames", repo: "No_Candidate" } },
            core: emptyFixture.core,
            configuredLabel: ""
        }),
        "No online idle runner"
    );

    const concurrentFixture = createFixture([
        runner(20, "candidate-a", ["self-hosted", "macOS", "unity-mobile"]),
        runner(21, "candidate-b", ["self-hosted", "macOS", "unity-mobile"])
    ], (runners, parameters) => {
        const other = runners.find((item) => item.id !== parameters.runner_id);
        other.labels.push({ name: parameters.labels[0] });
        return runners;
    });
    const reconciled = await allocator.allocate({
        github: concurrentFixture.github,
        context: { repo: { owner: "ActionFitGames", repo: "Concurrent" } },
        core: concurrentFixture.core,
        configuredLabel: ""
    });
    assert.strictEqual(reconciled.mode, "assigned");
    assert.strictEqual(
        concurrentFixture.github
            ? concurrentFixture.requests.filter((request) => request.route.startsWith("DELETE ")).length
            : 0,
        1
    );

    console.log("Runner allocator tests passed");
}

run().catch((error) => {
    console.error(error);
    process.exit(1);
});

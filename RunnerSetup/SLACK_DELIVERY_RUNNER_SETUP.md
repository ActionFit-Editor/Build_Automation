# Dedicated Slack Delivery Runner Setup

This guide configures one trusted self-hosted runner to deliver BuildCommit notifications for multiple Unity projects that share a Slack channel. Repository GitHub Secrets are not used for Slack.

## Architecture

The Unity build and Slack delivery paths are intentionally separate:

```text
BuildCommit Auto Build
  -> Unity runner builds and uploads GitHub Artifacts
  -> BuildCommit Slack Delivery receives workflow_run
  -> slack-delivery runner reads its host-local Slack bundle
  -> Slack webhook or Development APK file post
```

Unity runners never read Slack credentials and never post directly to Slack. `BuildCommit Slack Delivery` listens to exact `BuildCommit Auto Build` `in_progress` and `completed` events. It runs only for same-repository `push` or `workflow_dispatch` sources and requests both the `slack-delivery` runner group and `slack-delivery` label.

The delivery workflow does not use `actions/checkout` and does not execute source repository scripts. It fetches only `.build/build_request.json` from `workflow_run.head_sha` through `gh api`, validates that metadata with the fixed host-local delivery executable, and uses read-only `contents` and `actions` permissions. On successful Development Android completion it downloads only the uniquely named APK Artifact from that exact source run and attempt.

## Host Layout

The default installation root is fixed for the workflow template. Executables live in `/Users/lydia/workspace/slack-delivery/bin` and the shared credential bundle lives in `/Users/lydia/workspace/slack-delivery/secrets/shared`:

```text
/Users/lydia/workspace/slack-delivery/
  bin/
    deliver-buildcommit-slack
    notify-slack-build-result.sh
    upload-slack-file.sh
  secrets/
    shared/
      slack-webhook-url
      slack-bot-token
      slack-channel-id
```

Directories use mode `700`, secret files use mode `600`, and installed tools use mode `700`. Do not put these three Slack files under `/Users/lydia/workspace/build-automation`; that location belongs to Unity mobile build credentials.

## Install Host Tools

Run the installer from a trusted checkout that contains the Unity package. Use `.` when the Unity project is at the repository root or its repository-relative directory when nested:

```bash
cd /path/to/trusted/repository
UNITY_PROJECT_PATH="KnitFactory" # Use "." for a repository-root Unity project.
UNITY_PROJECT_DIR="$(pwd)/$UNITY_PROJECT_PATH"

bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/install-slack-delivery-tool.sh"
```

The installer creates placeholders without replacing existing secret values. Its default destination is `/Users/lydia/workspace/slack-delivery`. `SLACK_DELIVERY_ROOT` may override that destination for testing, but the shipped workflow calls the default absolute executable path, so production must use the default unless the workflow contract is deliberately changed.

Put one value on the first non-comment line of each file:

- `slack-webhook-url`: shared-channel Incoming Webhook URL for start, failure, cancellation, and non-APK success messages.
- `slack-bot-token`: Bot token with `files:write` for Development APK upload.
- `slack-channel-id`: shared destination channel ID. The Bot must already be a channel member.

Reapply permissions after editing:

```bash
find "/Users/lydia/workspace/slack-delivery/secrets" -type d -exec chmod 700 {} \;
find "/Users/lydia/workspace/slack-delivery/secrets" -type f -exec chmod 600 {} \;
test -x "/Users/lydia/workspace/slack-delivery/bin/deliver-buildcommit-slack"
```

## Configure GitHub Runner Access

1. Create an organization runner group named `slack-delivery`.
2. Set the group repository access policy to **Selected repositories**.
3. Add only repositories whose reviewed `BuildCommit Auto Build` and `BuildCommit Slack Delivery` workflows are trusted to use this runner.
4. Register a dedicated self-hosted runner in that group and give it the custom label `slack-delivery`.
5. Install and start the runner service, then confirm it is online in the expected group with that label.

Do not grant the runner group access to all repositories for convenience. The workflow has same-repository and source-event gates, but runner group access remains the outer scheduling boundary. Selected-repository access is the rollout state; the exact workflow allowlist described below is the final state.

## Publish The Workflow

Synchronize both package workflow templates into every trusted repository:

```text
.github/workflows/buildcommit-auto-build.yml
.github/workflows/buildcommit-slack-delivery.yml
```

`buildcommit-slack-delivery.yml` must be merged into the repository's default branch before GitHub will trigger it through `workflow_run`. A copy that exists only on a feature branch is not sufficient. Its source workflow name must remain exactly `BuildCommit Auto Build` unless both workflow contracts are intentionally updated.

## Restrict The Runner Group To Exact Workflows

GitHub validates selected-workflow entries when the runner group is updated and rejects an entry if that workflow file does not exist in the referenced repository and branch. Therefore use this order:

1. Keep group `slack-delivery` restricted to selected trusted repositories while rolling out.
2. Merge `.github/workflows/buildcommit-slack-delivery.yml` into each selected repository's `main` branch.
3. Set `restricted_to_workflows=true` and add one exact allowlist entry per repository:

```text
<org>/<repo>/.github/workflows/buildcommit-slack-delivery.yml@refs/heads/main
```

For example, the Cat Merge Cafe entry is:

```text
ActionFitGames/Cat_Merge_Cafe/.github/workflows/buildcommit-slack-delivery.yml@refs/heads/main
```

The organization runner-group API can apply the final restriction after all listed files exist. Replace the sample list with every trusted repository and no others:

```bash
ORG="ActionFitGames"
GROUP_ID="$(gh api "orgs/$ORG/actions/runner-groups" \
  --jq '.runner_groups[] | select(.name == "slack-delivery") | .id')"
test -n "$GROUP_ID"

gh api --method PATCH "orgs/$ORG/actions/runner-groups/$GROUP_ID" --input - <<'JSON'
{
  "name": "slack-delivery",
  "visibility": "selected",
  "allows_public_repositories": false,
  "restricted_to_workflows": true,
  "selected_workflows": [
    "ActionFitGames/Cat_Merge_Cafe/.github/workflows/buildcommit-slack-delivery.yml@refs/heads/main"
  ]
}
JSON
```

If a repository uses a different default branch, use that exact `refs/heads/<branch>` value consistently. Do not enable the final workflow restriction until every intended entry is accepted; selected-repository restriction remains the safe intermediate policy.

## Delivery Sequence

For an `in_progress` event:

1. GitHub schedules `BuildCommit Slack Delivery` on the `slack-delivery` group and label.
2. The workflow fetches the source revision's BuildRequest only, without source checkout or execution.
3. The host tool inspects schema 12 metadata and sends the start webhook notification for an approved BuildCommit request.

For a `completed` event:

1. The same metadata inspection runs again against the exact source `head_sha`.
2. A successful Development Android request downloads `Android-BuildCommit-Development-APK-<run-id>-<run-attempt>` from that source run only.
3. The host tool sends the success text and APK together as one Slack file post. Its initial comment includes the Development Build `[OK] ... BuildCommit SUCCESS` summary, so no separate success webhook is sent after a successful file post.
4. Other success, failure, and cancellation results use the webhook path.
5. Temporary metadata and Artifact files are removed with an `always()` cleanup step.

Notification, credential, Artifact download, and Slack API failures are advisory. They can produce warnings in `BuildCommit Slack Delivery`, but they never change the source Unity build conclusion. A Development APK remains in GitHub Artifacts when Slack delivery is unavailable.

## Security Boundary

A separate runner registration on the same Mac and under the same macOS user provides queue, label, and operational separation only. It is not credential isolation: any Unity workflow process running as that same user can read files that are mode `600` for the user.

Use a separate macOS user or a separate machine when the requirement is that Unity runner processes must be technically unable to read Slack credentials. Keep that account's home, runner service, working directory, and `/Users/lydia/workspace/slack-delivery` ownership inaccessible to the Unity runner account. If the fixed `/Users/lydia` workflow path is retained, a separate machine is the straightforward isolation option; a different-user installation requires intentionally changing the workflow's absolute host path.

Regardless of host placement:

- Never commit Slack credential files or store them in BuildRequest.
- Never add source checkout or source script execution to the privileged `workflow_run` workflow.
- Keep the runner group limited to selected trusted repositories.
- Review changes to the default-branch delivery workflow before deployment.
- Rotate the webhook and Bot token when runner access changes.

## Diagnosis

- **Delivery job remains queued:** confirm the runner is online, belongs to group `slack-delivery`, has label `slack-delivery`, and the group allows the repository.
- **No delivery workflow run appears:** confirm `buildcommit-slack-delivery.yml` is on the default branch and the source workflow name is exactly `BuildCommit Auto Build`.
- **Start/result webhook is missing:** check `secrets/shared/slack-webhook-url` on the delivery host. Do not move it to a repository Secret or Unity runner bundle.
- **Development APK is not attached:** confirm the source run succeeded, the request is Development Android, and the unique source-run Artifact exists. Then verify Bot `files:write`, `slack-channel-id`, and Bot channel membership.
- **Delivery shows warnings while the build is green:** this is the intended advisory failure boundary. Recover Slack delivery separately; do not rebuild solely to change the source build conclusion.

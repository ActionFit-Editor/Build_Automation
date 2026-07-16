# AI Mac Studio Build Automation Guide

Read this file when an AI assistant is asked to set up or diagnose the Mac Studio self-hosted runner for BuildCommit.

## Goal

The runner must build from BuildCommit requests without GitHub Secrets for mobile credentials. Android signing comes from the request first, while BuildCommit selects runner-local profiles for upload and iOS credentials:

- `distributionProfile`: `Actionfit` or `Stormborn`
- `platform`: `Android`, `iOS`, or `Both`
- schema 12 build metadata such as `unityProjectPath`, `autoConfigureBuildSymbols`, `developmentBuild`, version, bundle number, build kind, upload target, package name, bundle id, and optional non-secret Android alias

BuildRequest carries the project-specific Android keystore Base64 and signing passwords. The local bundle selected by `CI_SECRET_ROOT` provides Android fallbacks plus upload credentials, team ids, Apple Distribution `.p12` files, App Store provisioning profiles, and optional keychain settings. The scripts default to `$HOME/ci-secrets/build-automation`. BuildRequest never carries runner-local paths. Unity build runners never read Slack credentials; a separate `slack-delivery` runner owns those credentials and notifications.

## Files In This Package

- `WorkflowTemplates/buildcommit-auto-build.yml`: source workflow template.
- `WorkflowTemplates/buildcommit-slack-delivery.yml`: dedicated `workflow_run` Slack delivery template.
- `.github/actions/build-android/action.yml` and `.github/actions/build-ios/action.yml`: platform build/deploy composite actions synchronized with the workflow.
- `.github/scripts/resolve-unity-project.sh`: validates schema 12 `unityProjectPath` and exports repository/project-derived paths.
- `RunnerSetup/setup-local-runner-secrets.sh`: creates local directory and `.env` templates.
- `RunnerSetup/validate-local-runner-secrets.sh`: validates local files and exports env vars for GitHub Actions.
- `.github/scripts/prepare-actionfit-private-package-access.sh`: prepares GitHub credentials for private UPM package repositories before Unity starts.
- `RunnerSetup/install-slack-delivery-tool.sh` and `RunnerSetup/deliver-buildcommit-slack`: install and run the fixed host-local Slack delivery tool.
- `RunnerSetup/SLACK_DELIVERY_RUNNER_SETUP.md`: dedicated Slack runner setup and security guide.
- `RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md`: human-facing setup guide.
- `MAC_SELF_HOSTED_RUNNER_SETUP.md`: full Mac runner setup guide.

## Workflow Secret Root

```bash
$HOME/ci-secrets/build-automation
```

The scripts use this location by default. Set `CI_SECRET_ROOT` in the runner environment only when overriding it; do not add the path to BuildCommit request JSON.

## Setup Steps

1. Confirm the GitHub Actions runner service runs as the same macOS user that owns the secret root.
2. From the repository root, set the Unity project directory and create templates:

```bash
UNITY_PROJECT_PATH="KnitFactory" # Use "." for a repository-root Unity project.
UNITY_PROJECT_DIR="$(pwd)/$UNITY_PROJECT_PATH"
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh" \
  "$HOME/ci-secrets/build-automation"
```

3. Place real secret files and fill the `.env` files described in `LOCAL_RUNNER_SECRETS_GUIDE.md`.
4. Run `gh auth setup-git --hostname github.com` as the runner user, or put a read-only package token at `$HOME/ci-secrets/build-automation/shared/github-package-read-token`.
5. Do not put Slack credentials in this Unity runner bundle. Configure the separate runner using `SLACK_DELIVERY_RUNNER_SETUP.md`. Slack member mentions remain request metadata: AutoBuild reads shared `BuildAutomationSettingsSO` mention rows and serializes only `Mention`-enabled Member ID values into `.build/build_request.json` as the `slackMentions` JSON array. AutoBuild memo values stay in the shared SO and are not committed into the request JSON.
6. Validate before running GitHub Actions:

```bash
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  Actionfit Android GooglePlayInternal
```

7. Test Android first, then iOS, then Both.

The workflow runs `allocate` on the dedicated `mobile-build-allocator` runner group with the `runner-allocator` label before mobile scheduling. It calls `/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner` without repository checkout. `UNITY_RUNNER_AFFINITY_LABEL` may override the project label; otherwise the allocator derives it from the repository name. The host-local allocator uses the Mac user's `gh` Keychain authentication and a global file lock, reuses an existing online mapping, or assigns the least-loaded online `unity-mobile` runner while excluding CI and allocator labels. The following `mobile-build` job verifies the selected runner, refreshes the affinity retention marker, keeps Both on that workspace, preserves its local Unity `Library`, and performs only the required platform switch.

Slack delivery is a separate execution path. `BuildCommit Slack Delivery` listens to exact `BuildCommit Auto Build` `in_progress` and `completed` `workflow_run` events and requests both runner group and label `slack-delivery`. It accepts only same-repository `push` and `workflow_dispatch` sources. It fetches `.build/build_request.json` at the source `head_sha` through `gh api`, never checks out or executes repository source, and invokes `/Users/lydia/workspace/slack-delivery/bin/deliver-buildcommit-slack`. Verified Development APK posts persist a mode `600` source run/attempt receipt under `/Users/lydia/workspace/slack-delivery/receipts`; reruns reuse it instead of posting the APK twice, then retry idempotent Artifact cleanup. The delivery workflow must be merged into the repository default branch before GitHub emits usable `workflow_run` deliveries. Use selected-repository group access during rollout. After the delivery file exists on every allowed repository's default branch, set `restricted_to_workflows=true` and allow only exact `<org>/<repo>/.github/workflows/buildcommit-slack-delivery.yml@refs/heads/<default-branch>` entries. GitHub rejects allowlist entries for workflow files that do not exist yet.

## Diagnosis Rules

- If Android Unity signing fails, verify the request's keystore Base64 and signing fields first, then check runner fallback values `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, and `ANDROID_KEYALIAS_PASS` for any missing request value.
- If Unity files are not found, inspect repository-root request `unityProjectPath` and the `Resolve Unity project` output. Workflow/scripts stay in repository-root `.github`, while `Packages`, `ProjectSettings`, `Library`, `Builds`, and `Logs` are under `$UNITY_PROJECT_DIR`.
- If allocation fails, verify that the dedicated allocator runner is online in the expected group, the host-local executable is available, its `gh` authentication can manage organization runner labels, and at least one online candidate has `unity-mobile` without CI or allocator labels.
- If `mobile-build` remains queued after successful allocation, compare the allocator output with the online runner's `project-*` label.
- If Both performs a full reimport, confirm checkout uses `clean: false`, the pre-checkout reset does not pass `-x` to `git clean`, and runner-local `Library/SourceAssetDB` exists. Remote cache restore is only a cold fallback and is not saved by this workflow.
- If automatic build symbols fail, verify `autoConfigureBuildSymbols`, `com.actionfit.customsymbols@1.0.6`, and `CustomSymbolsSO` platform/Build checks. Missing settings are created from the current project defines before the target-switch process prepares symbols; the separate build process then verifies them.
- If Unity package resolution fails for private GitHub packages, check the `Prepare private package access` step, `gh auth status --hostname github.com`, and `shared/github-package-read-token`.
- If Slack notifications do not arrive, inspect the separate `BuildCommit Slack Delivery` run. Confirm its workflow exists on the default branch, the `slack-delivery` group permits this repository, a runner with the `slack-delivery` label is online, and `/Users/lydia/workspace/slack-delivery/secrets/shared/slack-webhook-url` is populated. For Development APK delivery also check the Bot token `files:write` scope, channel membership, the uniquely named source-run Artifact, and that `receipts` is an owner-controlled mode `700` directory. A malformed receipt deliberately fails closed to prevent duplicate posting. Required APK delivery failures fail only the separate delivery workflow and never change the source build conclusion. If notifications arrive without mentions, check `.build/build_request.json` `slackMentions` and use Slack member IDs such as `U12345678`, not display names.
- If Google Play upload fails, check `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` and the package name in `.build/build_request.json`.
- If iOS Xcode project has no team id, verify the `Resolve local runner secrets` step runs before Unity iOS build and exports `IOS_DEVELOPMENT_TEAM_ID`.
- If iOS signing fails before archive/export, verify `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_APP_STORE_PROVISIONING_PROFILE_DIR`, and that `ios/profiles/<iosBundleId>.mobileprovision` includes the `.p12` Apple Distribution certificate. If the file is missing, check `IOS_PROVISIONING_PROFILE_AUTO_GENERATE` and the `fastlane sigh` log.
- If archive/export tries cloud-managed signing, verify `ExportOptions.plist` uses manual signing and that `xcodebuild -exportArchive` is not using `-allowProvisioningUpdates`.
- If TestFlight upload fails, check `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_PATH`, and the request `iosBundleId`.

## Do Not

- Do not commit files under `ci-secrets`.
- Do not place Slack credentials in `/Users/lydia/workspace/build-automation` or expose them to Unity build workflow steps. They belong under `/Users/lydia/workspace/slack-delivery/secrets/shared`.
- Do not print Android keystore bytes/passwords from `.build/build_request.json`. Google Play, App Store Connect, certificate, and keychain credential values remain runner-local.
- Do not add GitHub Secrets for these mobile credentials unless explicitly replacing the runner-local secret bundle architecture.
- Do not run untrusted pull request workflows on the self-hosted runner.
- Do not describe two runner registrations under one macOS account as credential isolation. Use a separate macOS user or separate machine when the Unity runner must be technically unable to read Slack credentials.

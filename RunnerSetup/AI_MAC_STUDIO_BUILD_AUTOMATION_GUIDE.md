# AI Mac Studio Build Automation Guide

Read this file when an AI assistant is asked to set up or diagnose the Mac Studio self-hosted runner for BuildCommit.

## Goal

The runner must build from BuildCommit requests without GitHub Secrets for mobile credentials. Android signing comes from the request first, while BuildCommit selects runner-local profiles for upload and iOS credentials:

- `distributionProfile`: `Actionfit` or `Stormborn`
- `platform`: `Android`, `iOS`, or `Both`
- schema 11 build metadata such as `unityProjectPath`, `autoConfigureBuildSymbols`, version, bundle number, build kind, upload target, package name, bundle id, and optional non-secret Android alias

BuildRequest carries the project-specific Android keystore Base64 and signing passwords. The local bundle selected by `CI_SECRET_ROOT` provides Android fallbacks plus upload credentials, team ids, Apple Distribution `.p12` files, App Store provisioning profiles, and optional keychain settings. The scripts default to `$HOME/ci-secrets/build-automation`. BuildRequest never carries runner-local paths.

## Files In This Package

- `WorkflowTemplates/buildcommit-auto-build.yml`: source workflow template.
- `.github/scripts/resolve-unity-project.sh`: validates schema 11 `unityProjectPath` and exports repository/project-derived paths.
- `RunnerSetup/setup-local-runner-secrets.sh`: creates local directory and `.env` templates.
- `RunnerSetup/validate-local-runner-secrets.sh`: validates local files and exports env vars for GitHub Actions.
- `.github/scripts/prepare-actionfit-private-package-access.sh`: prepares GitHub credentials for private UPM package repositories before Unity starts.
- `.github/scripts/notify-slack-build-result.sh`: sends optional Android/iOS BuildCommit start/result notifications to Slack from the runner local webhook file.
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
5. Optional: put the Slack Incoming Webhook URL at `$HOME/ci-secrets/build-automation/shared/slack-webhook-url` to enable BuildCommit start/result notifications. Start messages use `[Start]`, and result messages include elapsed `Time`. Slack member mentions are not stored in this local bundle; AutoBuild reads shared `BuildAutomationSettingsSO` mention rows and serializes only `Mention`-enabled Member ID values into `.build/build_request.json` as the `slackMentions` JSON array. AutoBuild memo values stay in the shared SO and are not committed into the request JSON.
6. Validate before running GitHub Actions:

```bash
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  Actionfit Android GooglePlayInternal
```

7. Test Android first, then iOS, then Both.

## Diagnosis Rules

- If Android Unity signing fails, verify the request's keystore Base64 and signing fields first, then check runner fallback values `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, and `ANDROID_KEYALIAS_PASS` for any missing request value.
- If Unity files are not found, inspect repository-root request `unityProjectPath` and the `Resolve Unity project` output. Workflow/scripts stay in repository-root `.github`, while `Packages`, `ProjectSettings`, `Library`, `Builds`, and `Logs` are under `$UNITY_PROJECT_DIR`.
- If automatic build symbols fail, verify `autoConfigureBuildSymbols`, `com.actionfit.customsymbols@1.0.5`, and `CustomSymbolsSO` platform/Build checks. The target-switch process prepares symbols and the separate build process verifies them.
- If Unity package resolution fails for private GitHub packages, check the `Prepare private package access` step, `gh auth status --hostname github.com`, and `shared/github-package-read-token`.
- If Slack notifications do not arrive, check the `Notify Slack ... start/result` steps and `shared/slack-webhook-url`. Missing or invalid webhook files are treated as notification skip, not build failure. If notifications arrive without mentions, check `.build/build_request.json` `slackMentions` and use Slack member IDs such as `U12345678`, not display names.
- If Google Play upload fails, check `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` and the package name in `.build/build_request.json`.
- If iOS Xcode project has no team id, verify the `Resolve local runner secrets` step runs before Unity iOS build and exports `IOS_DEVELOPMENT_TEAM_ID`.
- If iOS signing fails before archive/export, verify `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_APP_STORE_PROVISIONING_PROFILE_DIR`, and that `ios/profiles/<iosBundleId>.mobileprovision` includes the `.p12` Apple Distribution certificate. If the file is missing, check `IOS_PROVISIONING_PROFILE_AUTO_GENERATE` and the `fastlane sigh` log.
- If archive/export tries cloud-managed signing, verify `ExportOptions.plist` uses manual signing and that `xcodebuild -exportArchive` is not using `-allowProvisioningUpdates`.
- If TestFlight upload fails, check `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_PATH`, and the request `iosBundleId`.

## Do Not

- Do not commit files under `ci-secrets`.
- Do not print Android keystore bytes/passwords from `.build/build_request.json`. Google Play, App Store Connect, certificate, and keychain credential values remain runner-local.
- Do not add GitHub Secrets for these mobile credentials unless explicitly replacing the runner-local secret bundle architecture.
- Do not run untrusted pull request workflows on the self-hosted runner.

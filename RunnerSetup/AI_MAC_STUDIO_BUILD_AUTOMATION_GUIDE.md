# AI Mac Studio Build Automation Guide

Read this file when an AI assistant is asked to set up or diagnose the Mac Studio self-hosted runner for BuildCommit.

## Goal

The runner must build from BuildCommit requests without GitHub Secrets for mobile credentials. BuildCommit selects:

- `distributionProfile`: `Actionfit` or `Stormborn`
- `platform`: `Android`, `iOS`, or `Both`
- build metadata such as version, bundle number, build kind, upload target, package name, bundle id, Android keystore bytes, Android alias, and Android signing passwords copied from BuildSetting

The runner restores Android keystore bytes from the request first. Upload credentials, team ids, Apple Distribution `.p12` files, App Store provisioning profiles, optional keychain settings, and optional Android fallback files come from the local bundle selected by workflow `CI_SECRET_ROOT`. This project sets it to `/Users/lydia/workspace/build-automation`.

## Files In This Package

- `WorkflowTemplates/buildcommit-auto-build.yml`: source workflow template.
- `RunnerSetup/setup-local-runner-secrets.sh`: creates local directory and `.env` templates.
- `RunnerSetup/validate-local-runner-secrets.sh`: validates local files and exports env vars for GitHub Actions.
- `RunnerSetup/LOCAL_RUNNER_SECRETS_GUIDE.md`: human-facing setup guide.
- `MAC_SELF_HOSTED_RUNNER_SETUP.md`: full Mac runner setup guide.

## Workflow Secret Root

```bash
$HOME/workspace/build-automation
```

Set `CI_SECRET_ROOT` in `.github/workflows/buildcommit-auto-build.yml`. Do not add this path to BuildCommit request JSON.

## Setup Steps

1. Confirm the GitHub Actions runner service runs as the same macOS user that owns the secret root.
2. From the repository root, create templates:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh \
  "$HOME/workspace/build-automation"
```

3. Place real secret files and fill the `.env` files described in `LOCAL_RUNNER_SECRETS_GUIDE.md`.
4. Validate before running GitHub Actions:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh \
  Actionfit Android GooglePlayInternal
```

5. Test Android first, then iOS, then Both.

## Diagnosis Rules

- If Android Unity signing fails, check `androidKeystoreBase64`, `androidKeystoreFileName`, `androidKeyaliasName`, `androidKeystorePassword`, and `androidAliasPassword` from `.build/build_request.json`. `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, and `ANDROID_KEYALIAS_PASS` are fallback env values only.
- If Google Play upload fails, check `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` and the package name in `.build/build_request.json`.
- If iOS Xcode project has no team id, verify the `Resolve local runner secrets` step runs before Unity iOS build and exports `IOS_DEVELOPMENT_TEAM_ID`.
- If iOS signing fails before archive/export, verify `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_APP_STORE_PROVISIONING_PROFILE_DIR`, and that `ios/profiles/<iosBundleId>.mobileprovision` includes the `.p12` Apple Distribution certificate. If the file is missing, check `IOS_PROVISIONING_PROFILE_AUTO_GENERATE` and the `fastlane sigh` log.
- If archive/export tries cloud-managed signing, verify `ExportOptions.plist` uses manual signing and that `xcodebuild -exportArchive` is not using `-allowProvisioningUpdates`.
- If TestFlight upload fails, check `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_PATH`, and the request `iosBundleId`.

## Do Not

- Do not commit files under `ci-secrets`.
- Do not paste Google Play, App Store Connect, or keychain credential values into `.build/build_request.json`. Android keystore bytes and signing passwords are serialized there intentionally by BuildCommit for this test flow.
- Do not add GitHub Secrets for these mobile credentials unless explicitly reverting to the older fallback model.
- Do not run untrusted pull request workflows on the self-hosted runner.

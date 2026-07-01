# Local Runner Secrets Guide

This guide describes the local secret bundle used by the `BuildCommit Auto Build` workflow on a macOS self-hosted runner.

The BuildCommit request contains distribution profile, platform, build kind, upload target, app identifiers, version, bundle number, Android keystore bytes, Android alias, and Android signing passwords copied from BuildSetting. Google Play JSON, App Store Connect API keys, Apple Distribution certificates, and App Store provisioning profiles stay on the Mac runner.

## Directory Layout

Workflow root:

```bash
$HOME/workspace/build-automation
```

The workflow declares this path in `.github/workflows/buildcommit-auto-build.yml` as `CI_SECRET_ROOT` using the absolute runner path `/Users/lydia/workspace/build-automation`. BuildCommit requests do not carry runner-local paths. The setup and validation scripts keep the same path as their local fallback so manual terminal checks match CI.

Expected files:

```bash
workspace/build-automation/
  shared/
    android-signing.env
    ios-keychain.env
    github-package-read-token
    slack-webhook-url
  profiles/
    actionfit/
      profile.env
      android-signing.env
      android/
        upload.keystore
        google-play-service-account.json
      ios/
        AuthKey_Actionfit.p8
        AppleDistribution_Actionfit.p12
        profiles/
          com.actionfit.catmerge.ios.mobileprovision
    stormborn/
      profile.env
      android-signing.env
      android/
        upload.keystore
        google-play-service-account.json
      ios/
        AuthKey_Stormborn.p8
        AppleDistribution_Stormborn.p12
        profiles/
          com.stormborn.example.ios.mobileprovision
```

## Create Template Files

Run this from the repository root on the Mac runner:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh \
  "$HOME/workspace/build-automation"
```

Then copy the real secret files into the generated folders and fill the `.env` files.

## Env Files

`shared/android-signing.env`

```bash
ANDROID_KEYSTORE_PASS="..."
ANDROID_KEYALIAS_PASS="..."
```

This file is a fallback for manual or legacy requests where `.build/build_request.json` does not contain Android signing passwords. New BuildCommit requests use the Android passwords copied from BuildSetting first.

`profiles/actionfit/android-signing.env`

```bash
# ANDROID_KEYSTORE_PASS=""
# ANDROID_KEYALIAS_PASS=""
```

Leave profile override values commented to use `shared/android-signing.env`. Uncomment and fill them only when a manual or legacy request needs profile-specific fallback passwords. The workflow loads `shared/android-signing.env` first and then loads `profiles/<profile>/android-signing.env`, so profile values win. BuildCommit request passwords still win inside Unity.

`shared/ios-keychain.env`

```bash
IOS_KEYCHAIN_PASSWORD=""
IOS_KEYCHAIN_PATH=""
```

Leave both values blank for the normal portable setup. The workflow will create a temporary keychain for each run, import the profile-specific `.p12`, and delete the temporary keychain during cleanup. Set these only when the runner must use a specific persistent keychain.

`shared/github-package-read-token`

```bash
# Optional. Prefer `gh auth setup-git` on the runner user.
REPLACE_WITH_READ_ONLY_GITHUB_TOKEN
```

This file is used only when the runner user does not already have working `gh auth` Git credential setup. Put one read-only token on the first non-comment line. The token must be able to read private ActionFit GitHub package repositories used by `Packages/manifest.json`.

`shared/slack-webhook-url`

```bash
# Optional. Slack Incoming Webhook URL for build result notifications.
https://hooks.slack.com/services/...
```

This file is optional. When present, the workflow sends Android/iOS BuildCommit success and failure notifications to Slack. The message includes one summary line plus platform, result, distribution profile, commit, and GitHub Actions run URL. Leave the file commented or empty to skip Slack notifications.

`profiles/actionfit/profile.env`

```bash
ANDROID_KEYSTORE_PATH="$HOME/workspace/build-automation/profiles/actionfit/android/upload.keystore"
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="$HOME/workspace/build-automation/profiles/actionfit/android/google-play-service-account.json"
IOS_DEVELOPMENT_TEAM_ID="49W7A8489P"
APP_STORE_CONNECT_API_KEY_ID="..."
APP_STORE_CONNECT_ISSUER_ID="..."
APP_STORE_CONNECT_API_KEY_P8_PATH="$HOME/workspace/build-automation/profiles/actionfit/ios/AuthKey_Actionfit.p8"
IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="$HOME/workspace/build-automation/profiles/actionfit/ios/AppleDistribution_Actionfit.p12"
IOS_DISTRIBUTION_CERTIFICATE_PASSWORD="..."
IOS_APP_STORE_PROVISIONING_PROFILE_DIR="$HOME/workspace/build-automation/profiles/actionfit/ios/profiles"
IOS_PROVISIONING_PROFILE_AUTO_GENERATE="true"
```

`profiles/stormborn/profile.env` uses the same keys with Stormborn values.

`ANDROID_KEYSTORE_PATH` is a fallback for manual or legacy requests where `.build/build_request.json` does not contain `androidKeystoreBase64`. New BuildCommit requests restore the Android keystore file from request base64 first.

The workflow resolves the App Store provisioning profile from the BuildCommit request bundle id. For `iosBundleId=com.actionfit.catmerge.ios`, the default local file is:

```bash
$HOME/workspace/build-automation/profiles/actionfit/ios/profiles/com.actionfit.catmerge.ios.mobileprovision
```

The App Store provisioning profile must be for the same bundle id as the BuildCommit request and must include the Apple Distribution certificate stored in `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`. If the file is missing and `IOS_PROVISIONING_PROFILE_AUTO_GENERATE=true`, the workflow attempts `fastlane sigh` generation/download before archive/export.

The `.p12` must contain the Apple Distribution identity and private key for the same team as `IOS_DEVELOPMENT_TEAM_ID`. The validation script imports the `.p12` into a temporary keychain and fails before the Unity build if the team does not match.

## Permissions

The setup script applies these permissions:

```bash
find "$HOME/workspace/build-automation" -type d -exec chmod 700 {} \;
find "$HOME/workspace/build-automation" -type f -exec chmod 600 {} \;
```

Only the macOS user running the GitHub Actions runner should be able to read these files.

## Validate Locally

Android only:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh \
  Actionfit Android GooglePlayInternal
```

iOS only:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh \
  Actionfit iOS TestFlight
```

Both:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh \
  Actionfit Both GooglePlayInternalAndTestFlight
```

## Workflow Behavior

The workflow calls `prepare-actionfit-private-package-access.sh` and `validate-local-runner-secrets.sh` before Unity build steps.

Private package access:

- Runs `gh auth setup-git --hostname github.com` when the runner user already has `gh auth`.
- Falls back to `shared/github-package-read-token` or `ACTIONFIT_GITHUB_PACKAGE_READ_TOKEN`.
- Rewrites `git@github.com:` and `ssh://git@github.com/` package URLs to HTTPS so the same GitHub credential path can be used.
- Checks private package repository access with `git ls-remote` before Unity package resolution.

Slack notification:

- Runs `notify-slack-build-result.sh` at the end of each Android/iOS build job with `if: always()`.
- Reads `shared/slack-webhook-url` or `SLACK_BUILD_WEBHOOK_URL`.
- Reads optional BuildCommit request `slackMentions` through `SLACK_BUILD_MENTIONS` and prepends multiple Slack member mentions to the notification.
- Sends a short message with project/platform/version result, profile, commit, and GitHub Actions run URL. It intentionally omits separate `Project`, `Version`, `Upload`, and `Ref` lines.
- Sends both success and failure results.
- Skips without failing the build when the webhook file is missing, empty, invalid, or Slack POST fails.

Android:

- Restores `androidKeystoreBase64` from `.build/build_request.json` into `.build/ci-keystore/` and uses that file for Unity signing.
- Uses `ANDROID_KEYSTORE_PATH` only when the request does not contain keystore bytes.
- Uses `androidKeystorePassword` and `androidAliasPassword` from `.build/build_request.json`; `ANDROID_KEYSTORE_PASS` and `ANDROID_KEYALIAS_PASS` are fallback values.
- Uses `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` for Google Play upload.

iOS:

- Injects `IOS_DEVELOPMENT_TEAM_ID` before Unity generates the Xcode project.
- Uses `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_P8_PATH` for TestFlight upload.
- Creates a temporary keychain by default, imports `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`, and grants codesign access.
- Resolves the App Store provisioning profile from `IOS_APP_STORE_PROVISIONING_PROFILE_DIR/<iosBundleId>.mobileprovision`; `IOS_APP_STORE_PROVISIONING_PROFILE_PATH` is still supported as an explicit override.
- If the resolved profile is missing and `IOS_PROVISIONING_PROFILE_AUTO_GENERATE=true`, runs `fastlane sigh` to create/download it.
- Validates that the resolved provisioning profile matches `IOS_DEVELOPMENT_TEAM_ID`, the request bundle id, and the imported Apple Distribution certificate.
- Exports the `.ipa` with manual App Store signing, using the installed profile name in `ExportOptions.plist`.

## Security Rule

Do not allow untrusted workflow code to run on this runner. Any workflow running on the self-hosted Mac can read files that the runner user can read. Keep BuildCommit triggers limited to trusted tags/branches and do not run arbitrary pull request workflows on this runner.

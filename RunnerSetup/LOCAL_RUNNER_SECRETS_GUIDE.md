# Local Runner Secrets Guide

This guide describes the local secret bundle used by the `BuildCommit Auto Build` workflow on a macOS self-hosted runner.

BuildRequest schema 12 contains build metadata plus project-specific Android keystore Base64 and signing passwords. Android request values take precedence, while the Mac runner bundle provides optional Android fallbacks and remains the source for Google Play JSON, iOS team and App Store Connect credentials, Apple Distribution certificates, and provisioning profiles.

## Directory Layout

Workflow root:

```bash
/Users/lydia/workspace/build-automation
```

The workflow template sets `CI_SECRET_ROOT=/Users/lydia/workspace/build-automation` so existing ActionFit self-hosted runners continue to use their current bundle. Setup and validation scripts invoked without that environment variable still default to `$HOME/ci-secrets/build-automation`. BuildCommit requests do not carry runner-local paths; override `CI_SECRET_ROOT` when a runner uses another location.

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

Run this from the repository root on the Mac runner. Use `.` when Unity is at the repository root or the repository-relative directory when it is nested:

```bash
UNITY_PROJECT_PATH="KnitFactory" # Use "." for a repository-root Unity project.
UNITY_PROJECT_DIR="$(pwd)/$UNITY_PROJECT_PATH"

bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh" \
  "/Users/lydia/workspace/build-automation"
```

Then copy the real secret files into the generated folders and fill the `.env` files.

## Env Files

`shared/android-signing.env`

```bash
ANDROID_KEYSTORE_PASS="..."
ANDROID_KEYALIAS_PASS="..."
```

These values are fallbacks for Android BuildCommit requests that omit the corresponding signing passwords.

`profiles/actionfit/android-signing.env`

```bash
# ANDROID_KEYSTORE_PASS=""
# ANDROID_KEYALIAS_PASS=""
```

Leave profile override values commented to use `shared/android-signing.env`. Uncomment them when profiles use different signing passwords. The workflow loads `shared/android-signing.env` first and then `profiles/<profile>/android-signing.env`, so profile values win.

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

This file is used only when the runner user does not already have working `gh auth` Git credential setup. Put one read-only token on the first non-comment line. The token must be able to read private ActionFit GitHub package repositories used by `$UNITY_PROJECT_DIR/Packages/manifest.json`.

`shared/slack-webhook-url`

```bash
# Optional. Slack Incoming Webhook URL for build start/result notifications.
https://hooks.slack.com/services/...
```

This file is optional. When present, the workflow sends Android/iOS BuildCommit start and result notifications to Slack. Start messages use `[Start]`, and result messages include one summary line plus elapsed `Time`, distribution profile, commit, and GitHub Actions run URL. Leave the file commented or empty to skip Slack notifications.

`shared/slack-bot-token` and `shared/slack-channel-id`

```bash
# slack-bot-token: Bot token with files:write. Never commit this value.
xoxb-...

# slack-channel-id: target channel ID; the bot must already be a member.
C12345678
```

These files are optional and used only for direct Development Android APK attachment. The workflow uses Slack's external upload URL and completion APIs. Missing/invalid configuration or an API failure emits a warning and leaves the APK in the `Android-BuildCommit-Development-APK` GitHub Artifact without failing a successful build. No SMB/NAS or persistent workspace file share is used.

`profiles/actionfit/profile.env`

```bash
ANDROID_KEYSTORE_PATH="/Users/lydia/workspace/build-automation/profiles/actionfit/android/upload.keystore"
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="/Users/lydia/workspace/build-automation/profiles/actionfit/android/google-play-service-account.json"
IOS_DEVELOPMENT_TEAM_ID="49W7A8489P"
APP_STORE_CONNECT_API_KEY_ID="..."
APP_STORE_CONNECT_ISSUER_ID="..."
APP_STORE_CONNECT_API_KEY_P8_PATH="/Users/lydia/workspace/build-automation/profiles/actionfit/ios/AuthKey_Actionfit.p8"
IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="/Users/lydia/workspace/build-automation/profiles/actionfit/ios/AppleDistribution_Actionfit.p12"
IOS_DISTRIBUTION_CERTIFICATE_PASSWORD="..."
IOS_APP_STORE_PROVISIONING_PROFILE_DIR="/Users/lydia/workspace/build-automation/profiles/actionfit/ios/profiles"
IOS_PROVISIONING_PROFILE_AUTO_GENERATE="true"
```

`profiles/stormborn/profile.env` uses the same keys with Stormborn values.

`ANDROID_KEYSTORE_PATH` is required only when the BuildRequest does not contain `androidKeystoreBase64`. The runner password values are likewise required only when the corresponding request password is empty. Android alias metadata continues to come from the request.

The workflow resolves the App Store provisioning profile from the BuildCommit request bundle id. For `iosBundleId=com.actionfit.catmerge.ios`, the default local file is:

```bash
/Users/lydia/workspace/build-automation/profiles/actionfit/ios/profiles/com.actionfit.catmerge.ios.mobileprovision
```

The App Store provisioning profile must be for the same bundle id as the BuildCommit request and must include the Apple Distribution certificate stored in `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`. If the file is missing and `IOS_PROVISIONING_PROFILE_AUTO_GENERATE=true`, the workflow attempts `fastlane sigh` generation/download before archive/export.

The `.p12` must contain the Apple Distribution identity and private key for the same team as `IOS_DEVELOPMENT_TEAM_ID`. The validation script imports the `.p12` into a temporary keychain and fails before the Unity build if the team does not match.

## Permissions

The setup script applies these permissions:

```bash
find "/Users/lydia/workspace/build-automation" -type d -exec chmod 700 {} \;
find "/Users/lydia/workspace/build-automation" -type f -exec chmod 600 {} \;
```

Only the macOS user running the GitHub Actions runner should be able to read these files.

## Validate Locally

Android only:

```bash
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  Actionfit Android GooglePlayInternal
```

iOS only:

```bash
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  Actionfit iOS TestFlight
```

Both:

```bash
bash "$UNITY_PROJECT_DIR/Packages/com.actionfit.buildautomation/RunnerSetup/validate-local-runner-secrets.sh" \
  Actionfit Both GooglePlayInternalAndTestFlight
```

## Workflow Behavior

The workflow calls `prepare-actionfit-private-package-access.sh` and `validate-local-runner-secrets.sh` before Unity build steps. Manual validator runs never print credential values; GitHub `::add-mask::` commands are emitted only when `GITHUB_ACTIONS=true`.

Private package access:

- Runs `gh auth setup-git --hostname github.com` when the runner user already has `gh auth`.
- Falls back to `shared/github-package-read-token` or `ACTIONFIT_GITHUB_PACKAGE_READ_TOKEN`.
- Exports token helper settings through `GIT_CONFIG_*` into `GITHUB_ENV` so later workflow steps and Unity child Git processes keep the same private package credential.
- Rewrites `git@github.com:` and `ssh://git@github.com/` package URLs to HTTPS so the same GitHub credential path can be used.
- Checks private package repository access from `$UNITY_PROJECT_DIR/Packages/manifest.json` with `git ls-remote` before Unity package resolution.

Slack notification:

- Runs `notify-slack-build-result.sh` at the start of each Android/iOS build job and at the end with `if: always()`.
- Reads `shared/slack-webhook-url` or `SLACK_BUILD_WEBHOOK_URL`.
- Reads optional BuildCommit request `slackMentions` JSON array through `SLACK_BUILD_MENTIONS` and prepends multiple Slack member mentions to the notification. AutoBuild stores shared mention rows in `BuildAutomationSettingsSO`; only rows with `Mention` enabled enter the request, and memo values are not committed into `.build/build_request.json`.
- Sends a short message with one summary line plus time when available, profile, commit, and GitHub Actions run URL. It intentionally omits separate `Project`, `Version`, `Platform`, `Result`, `Upload`, and `Ref` lines.
- Sends `[Start]` messages plus success, failure, and cancelled results.
- Skips without failing the build when the webhook file is missing, empty, invalid, or Slack POST fails.
- Prefixes Development Build start/result summaries with `[DEVELOPMENT BUILD]`.
- Development Android additionally reads `shared/slack-bot-token` and `shared/slack-channel-id`, attaches the fresh APK through Slack Bot `files:write`, and falls back to the GitHub Artifact when attachment is unavailable.

Android:

- Validates and uses `androidKeystoreBase64`, `androidKeystorePassword`, and `androidAliasPassword` from the schema 12 BuildRequest when present.
- Falls back independently to `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, and `ANDROID_KEYALIAS_PASS` for missing request values.
- Uses the request's `androidKeyaliasName` metadata.
- Uses `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` for Google Play upload.

iOS:

- Injects `IOS_DEVELOPMENT_TEAM_ID` before Unity generates the Xcode project.
- Uses `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_P8_PATH` for TestFlight upload.
- Creates a temporary keychain by default, imports `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`, and grants codesign access.
- Resolves the App Store provisioning profile from `IOS_APP_STORE_PROVISIONING_PROFILE_DIR/<iosBundleId>.mobileprovision`; `IOS_APP_STORE_PROVISIONING_PROFILE_PATH` is still supported as an explicit override.
- If the resolved profile is missing and `IOS_PROVISIONING_PROFILE_AUTO_GENERATE=true`, runs `fastlane sigh` to create/download it.
- Validates that the resolved provisioning profile matches `IOS_DEVELOPMENT_TEAM_ID`, the request bundle id, and the imported Apple Distribution certificate.
- Exports the `.ipa` with manual App Store signing, using the installed profile name in `ExportOptions.plist`.

Project and symbols:

- Reads repository-root `.build/build_request.json`; only schema 12 is accepted and `unityProjectPath` resolves `$UNITY_PROJECT_DIR`.
- Derives `Packages`, `ProjectSettings`, `Library`, `Builds`, and `Logs` from `$UNITY_PROJECT_DIR`; workflow/scripts remain under repository-root `.github`.
- When `autoConfigureBuildSymbols=true`, prepares the Custom Symbols build list in the target-switch Unity process and verifies it in the separate build process.

## Security Rule

Do not allow untrusted workflow code to run on this runner. Any workflow running on the self-hosted Mac can read files that the runner user can read. Keep BuildCommit triggers limited to trusted tags/branches and do not run arbitrary pull request workflows on this runner. Android BuildRequest signing values must never be printed to workflow logs.

# Local Runner Secrets Guide

This guide describes the mobile build secret bundle used by the `BuildCommit Auto Build` workflow on a macOS self-hosted Unity runner.

BuildRequest schema 12 contains build metadata plus project-specific Android keystore Base64 and signing passwords. Android request values take precedence, while the shared Mac runner bundle provides optional Android fallbacks and remains the source for Google Play JSON, iOS team and App Store Connect credentials, Apple Distribution certificates, provisioning profiles, and Slack delivery credentials.

## Directory Layout

Workflow root:

```bash
/Users/lydia/workspace/build-automation
```

Set `CI_SECRET_ROOT` in each `unity-mobile` runner service environment. Mac Studio runners use `/Users/lydia/workspace/build-automation`; MacBook runners use their fixed SMB mountpoint. When it is not explicitly set, the workflow resolver checks `$HOME/workspace/build-automation`, `/Volumes/ActionFitBuildAutomation`, then `$HOME/ci-secrets/build-automation`. BuildCommit requests never carry runner-local paths.

Expected files:

```bash
workspace/build-automation/
  shared/
    android-signing.env
    ios-keychain.env
    github-package-read-token
    slack-webhook-url
    slack-bot-token
    slack-channel-id
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
  state/
    slack-apk-delivery/
      <repository-and-run-id-sha256>.json
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

`shared/slack-webhook-url` contains the optional Incoming Webhook URL used for one start notification and final failure/non-APK result notifications. `shared/slack-bot-token` contains a Bot token with `files:write`, and `shared/slack-channel-id` contains the common destination channel ID. The Bot must be a channel member. Development APKs are uploaded directly from the runner that created them; do not put these values in GitHub Secrets or BuildRequest.

`state/slack-apk-delivery` is created automatically with mode `0700`; each `0600` receipt records only repository/run identity, source commit, attempt number, Slack file ID, timestamps, and pending/delivered state. It never stores a token, upload URL, APK path, or APK bytes. Because this state prevents duplicate posts across runners and GitHub reruns, every trusted Unity runner must see the same writable state directory.

`profiles/actionfit/profile.env`

```bash
ANDROID_KEYSTORE_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/upload.keystore"
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="${CI_SECRET_ROOT}/profiles/actionfit/android/google-play-service-account.json"
IOS_DEVELOPMENT_TEAM_ID="49W7A8489P"
APP_STORE_CONNECT_API_KEY_ID="..."
APP_STORE_CONNECT_ISSUER_ID="..."
APP_STORE_CONNECT_API_KEY_P8_PATH="${CI_SECRET_ROOT}/profiles/actionfit/ios/AuthKey_Actionfit.p8"
IOS_DISTRIBUTION_CERTIFICATE_P12_PATH="${CI_SECRET_ROOT}/profiles/actionfit/ios/AppleDistribution_Actionfit.p12"
IOS_DISTRIBUTION_CERTIFICATE_PASSWORD="..."
IOS_APP_STORE_PROVISIONING_PROFILE_DIR="${CI_SECRET_ROOT}/profiles/actionfit/ios/profiles"
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

Only trusted macOS users running the Unity GitHub Actions runners should be able to read these files. When the bundle is exported from Mac Studio over SMB, disable guest access, require SMB3 encryption, and mount it before the MacBook runner service starts.

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

- The affinity `mobile-build` job sends one start webhook after resolving the shared bundle.
- Android exposes only the APK produced after its current phase marker. The top-level workflow waits for all requested platforms and deferred Store uploads to succeed before uploading that local file directly to Slack.
- A successful Development Android/Both request includes the success message in the APK post and skips a duplicate success webhook.
- Missing credentials, an unreadable APK, timeout, and Slack API failure are advisory. They produce `BUILD SUCCESS / APK DELIVERY FAILED` when the webhook is available and do not change the successful Unity build result.
- Direct API calls use bounded timeouts. No Development APK GitHub Artifact or separate Slack delivery runner is involved.
- A durable receipt keyed by repository and GitHub `run_id` prevents a rerun from posting the APK twice. Failures before Slack completion discard retry-safe state. Once completion is attempted, the pending receipt is preserved and duplicate uploads are blocked until an operator reconciles it.
- For an armed pending receipt, use the path and Slack file ID printed by the upload step. First check the destination channel. If the APK post exists, run the receipt manager's `complete <FILE_ID>` operation with the original repository/run/SHA environment to mark it delivered. If the post is definitely absent, stop all attempts for that run, remove only the logged receipt JSON, and rerun the GitHub job. Never delete pending receipts through automatic age/LRU cleanup. Delivered receipts are tiny and may be retained; prune them only under an explicit long-retention policy while no delivery is active.

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

Do not allow untrusted workflow code to run on these runners. Any workflow running as a user that can read the shared bundle can also read its Slack and Store credentials. Keep BuildCommit triggers limited to trusted tags/branches, restrict access to `unity-mobile` runners, and never run arbitrary pull request or `ci` workflows on them. Credential values must never be printed to workflow logs.

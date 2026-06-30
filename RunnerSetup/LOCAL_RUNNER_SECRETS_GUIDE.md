# Local Runner Secrets Guide

This guide describes the local secret bundle used by the `BuildCommit Auto Build` workflow on a macOS self-hosted runner.

The BuildCommit request contains distribution profile, platform, build kind, upload target, app identifiers, version, bundle number, Android alias, and Android signing passwords copied from BuildSetting. Keystore files, Google Play JSON, App Store Connect API keys, and keychain passwords stay on the Mac runner.

## Directory Layout

Default root:

```bash
$HOME/ci-secrets/cat-merge-cafe
```

The setup and validation scripts use the runner user's `$HOME` by default. Set `CI_SECRET_ROOT` only when the Mac Studio must store this bundle somewhere else.

Expected files:

```bash
ci-secrets/cat-merge-cafe/
  shared/
    android-signing.env
    ios-keychain.env
  profiles/
    actionfit/
      profile.env
      android-signing.env
      android/
        upload.keystore
        google-play-service-account.json
      ios/
        AuthKey_Actionfit.p8
    stormborn/
      profile.env
      android-signing.env
      android/
        upload.keystore
        google-play-service-account.json
      ios/
        AuthKey_Stormborn.p8
```

## Create Template Files

Run this from the repository root on the Mac runner:

```bash
bash Packages/com.actionfit.buildautomation/RunnerSetup/setup-local-runner-secrets.sh \
  "$HOME/ci-secrets/cat-merge-cafe"
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
IOS_KEYCHAIN_PASSWORD="..."
IOS_KEYCHAIN_PATH=""
```

Leave `IOS_KEYCHAIN_PATH` blank to use:

```bash
$HOME/Library/Keychains/login.keychain-db
```

`profiles/actionfit/profile.env`

```bash
ANDROID_KEYSTORE_PATH="$HOME/ci-secrets/cat-merge-cafe/profiles/actionfit/android/upload.keystore"
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="$HOME/ci-secrets/cat-merge-cafe/profiles/actionfit/android/google-play-service-account.json"
IOS_DEVELOPMENT_TEAM_ID="49W7A8489P"
APP_STORE_CONNECT_API_KEY_ID="..."
APP_STORE_CONNECT_ISSUER_ID="..."
APP_STORE_CONNECT_API_KEY_P8_PATH="$HOME/ci-secrets/cat-merge-cafe/profiles/actionfit/ios/AuthKey_Actionfit.p8"
```

`profiles/stormborn/profile.env` uses the same keys with Stormborn values.

## Permissions

The setup script applies these permissions:

```bash
find "$HOME/ci-secrets/cat-merge-cafe" -type d -exec chmod 700 {} \;
find "$HOME/ci-secrets/cat-merge-cafe" -type f -exec chmod 600 {} \;
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

The workflow calls `validate-local-runner-secrets.sh` before Unity build steps.

Android:

- Injects `ANDROID_KEYSTORE_PATH` into Unity batchmode.
- Uses `androidKeystorePassword` and `androidAliasPassword` from `.build/build_request.json`; `ANDROID_KEYSTORE_PASS` and `ANDROID_KEYALIAS_PASS` are fallback values.
- Uses `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` for Google Play upload.

iOS:

- Injects `IOS_DEVELOPMENT_TEAM_ID` before Unity generates the Xcode project.
- Uses `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_P8_PATH` for archive/export and TestFlight upload.
- Unlocks the runner keychain with `IOS_KEYCHAIN_PASSWORD`.

## Security Rule

Do not allow untrusted workflow code to run on this runner. Any workflow running on the self-hosted Mac can read files that the runner user can read. Keep BuildCommit triggers limited to trusted tags/branches and do not run arbitrary pull request workflows on this runner.

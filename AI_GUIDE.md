# AI Guide - Build Automation

This file is shipped inside the UPM package so an AI assistant in a consuming Unity project can understand the package without access to the source project's `Docs/AI` folder.

## Package Identity

- Package ID: `com.actionfit.buildautomation`
- Display name: Build Automation
- Repository: `https://github.com/ActionFit-Editor/Build_Automation.git`
- Current package version at generation time: `1.0.24`
- Unity version: `6000.2`

## Purpose

Build Automation owns BuildCommit request generation, Git tag based CI triggers, request JSON parsing, CI batchmode entry points, GitHub Actions workflow templates, local runner secret resolution, and macOS self-hosted mobile build guidance.

This package depends on `com.actionfit.buildsetting`. Keep build/player settings in Build Setting. Keep CI request orchestration and remote build workflow behavior in Build Automation.

## Project Router Registration

This package should be listed in `Packages/com.actionfit.custompackagemanager/PACKAGE_AI_GUIDE_ROUTER.md`.

Requested router entry:

- `Packages/com.actionfit.buildautomation/AI_GUIDE.md` - Build Automation manages BuildCommit requests, Git tag CI triggers, GitHub Actions mobile build workflows, and macOS self-hosted runner guidance. Read when changing automatic build request behavior, `.build/build_request.json`, workflow templates, or CI batchmode entry points.

If the router file is not already included in the AI assistant's default reading sequence, the router file is responsible for asking the user to link it from `Docs/AI/PROJECT.md` when available, or otherwise from `AGENTS.md`, `CLAUDE.md`, or another primary AI markdown entry point.

Read this file when:

- changing files under `Packages/com.actionfit.buildautomation/`
- changing `.github/workflows/buildcommit-auto-build.yml`
- diagnosing BuildCommit, Git tag build triggers, request JSON, CI build entry, or runner setup
- preparing a release for `com.actionfit.buildautomation`
- editing package metadata, README, AI guide, workflow templates, package version, or release notes

## Required Reading For AI

- Read this `AI_GUIDE.md` before changing, diagnosing, or explaining this package.
- Read `Packages/com.actionfit.custompackagemanager/PACKAGE_AI_GUIDE_ROUTER.md` when deciding which installed ActionFit package `AI_GUIDE.md` applies to a task.
- Read `Packages/com.actionfit.buildsetting/AI_GUIDE.md` before changing interfaces with `BuildSettingsSO`, `BuildSettingsApplier`, `AOSBuildProcess`, or `iOSBuildProcess`.
- Read `README.md` for human-facing setup and usage.
- Read `package.json` for package ID, version, Unity version, and dependencies.
- Read `Editor/PackageInfo/ActionFitPackageInfo_SO.asset` for catalog metadata, repository name, owner, status, description, release note, and dependency override.
- Read `Packages/com.actionfit.githubauth/AI_GUIDE.md` before changing BuildCommit local GitHub authentication preflight behavior or user guidance.

## Editing Rules

- Keep BuildCommit, request JSON, CI entry, workflow template, and runner setup changes in this package.
- Treat `WorkflowTemplates/*.yml`, package `.github/scripts/*.sh`, package README/AI guide updates, and package metadata changes as package source changes. Prepare a package release and bump `package.json` version when these files change; the consuming project's root `.github/workflows/*.yml` is only the synced project copy.
- Keep Android/iOS player/build settings and local build process implementations in `com.actionfit.buildsetting`.
- Do not change public menu paths, request JSON field names, enum numeric values, tag prefix, or CI entry method casually. Existing workflow triggers and stored request JSON depend on them.
- Preserve Unity `.meta` files when adding, moving, or renaming files inside the package.
- When behavior changes, update this `AI_GUIDE.md` and `README.md` before publishing so consuming projects receive the latest AI context.

## Behavior Notes

- Menu: `Tools/ActionFit/BuildSetting/AutoBuild`.
- Build request path: `.build/build_request.json`.
- Build tag prefix: `build/**`.
- Storage commit message prefix: `[BuildRequest]`.
- Distribution profile request field: `distributionProfile`. Current profiles are `Actionfit` and `Stormborn`; only the profile name is stored in request JSON.
- BuildCommit window starts with `Platform=None`. `Commit, Tag & Push` is disabled until the user selects `Current`, `Android`, `iOS`, or `Both`. `Current` remains a selectable option and resolves to the active Unity build target when the request is created.
- `Commit, Tag & Push` runs local `git push` and tag push from the Unity editor. Each developer machine that uses BuildCommit must have GitHub credentials configured for the consuming repository with push/tag permission. BuildCommit uses `GitHubAuthPreflight.EnsureProjectGitHubPushAccess` from `com.actionfit.githubauth` before creating the request commit/tag; on failure, GitHub Auth shows the shared authentication-required dialog and BuildCommit stops. BuildAutomation must not hard-reference `ActionFit.BuildSetting.Editor` or `ActionFit.GitHubAuth.Editor` in `using` statements or the editor asmdef, because missing Git UPM dependencies would prevent the package from compiling. Use `BuildSettingBridge` and reflection for optional calls. Leave dependency installation to ActionFit Package Manager's catalog CSV dependency flow; if editing `Packages/manifest.json` manually, all required Git UPM URLs must be added explicitly.
- When explaining or diagnosing local BuildCommit push failures, route detailed command sequences and error-specific guidance through `Packages/com.actionfit.githubauth/README.md` and `Packages/com.actionfit.githubauth/AI_GUIDE.md`. Treat `fatal: could not read Username for 'https://github.com': Device not configured` as a local GitHub credential/helper issue, not a workflow yml or GitHub Actions runner issue.
- BuildCommit window has `Auto Sync Build Files`, stored in `EditorPrefs` as `BuildCommitAutoSyncWorkflowAssets`, defaulting to true. When enabled, `Commit, Tag & Push` syncs package workflow assets into project `.github/` before saving the request and running `git add .`.
- Android request fields `androidKeystoreFileName`, `androidKeystoreBase64`, `androidKeyaliasName`, `androidKeystorePassword`, and `androidAliasPassword` are copied from `BuildSettingsSO.keyStorePath`, `BuildSettingsSO.keyStoreAlias`, `BuildSettingsSO.keystorePassword`, and `BuildSettingsSO.aliasPassword`. Android request keystore/password values are used first; local runner env values are fallback only.
- BuildCommit window platform changes reset default request options: Android uses `AndroidAab` and `GooglePlayInternal`; iOS uses `iOSXcodeProject` and `TestFlight`; Both uses `AndroidAabAndiOSXcodeProject` and `GooglePlayInternalAndTestFlight`.
- App identifier request fields: `androidPackageName`, copied from `BuildSettingsSO.androidPackageName`, and `iosBundleId`, copied from `BuildSettingsSO.iosPackageName`. The workflow uses these request values for Google Play `packageName` and TestFlight `app_identifier`.
- Google Play JSON, App Store Connect P8, Apple Distribution `.p12`, App Store provisioning profiles, and optional keychain passwords must stay out of `.build/build_request.json`. Android keystore file bytes and signing passwords are intentionally serialized from BuildSetting for BuildCommit request testing.
- Non-request credential source is the Mac runner local secret bundle selected by workflow `CI_SECRET_ROOT`; this project sets it to `/Users/lydia/workspace/build-automation`. BuildCommit requests must not carry runner-local paths. The bundle provides optional `ANDROID_KEYSTORE_PATH` and Android password fallbacks, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`, `IOS_DEVELOPMENT_TEAM_ID`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_PATH`, `IOS_DISTRIBUTION_CERTIFICATE_P12_PATH`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_APP_STORE_PROVISIONING_PROFILE_DIR`, optional `IOS_APP_STORE_PROVISIONING_PROFILE_PATH`, `IOS_PROVISIONING_PROFILE_AUTO_GENERATE`, optional `IOS_KEYCHAIN_PASSWORD`, and optional `IOS_KEYCHAIN_PATH`. iOS export uses manual App Store signing from these local files.
- Workflow Unity resolution calls the project-root `.github/scripts/resolve-unity-editor.sh`. The script reads `ProjectSettings/ProjectVersion.txt`, exports `UNITY_VERSION`, `UNITY_VERSION_WITH_REVISION`, and `UNITY_EXECUTABLE`, and fails early if that editor is not installed under `UNITY_HUB_EDITOR_ROOT`.
- Workflow secret validation calls the project-root `.github/scripts/validate-local-runner-secrets.sh`. The package keeps source copies under `.github/scripts/`, and the AutoBuild workflow sync button copies them into the consuming project together with the workflow yml. Do not make pre-Unity shell steps depend on `Packages/` or `Library/PackageCache`.
- Workflow private package access preparation calls the project-root `.github/scripts/prepare-actionfit-private-package-access.sh` before Unity starts. It configures GitHub HTTPS access from runner `gh auth` or from `CI_SECRET_ROOT/shared/github-package-read-token`, rewrites GitHub SSH package URLs to HTTPS, and preflights ActionFit GitHub package repositories listed in `Packages/manifest.json`.
- Workflow Slack notification calls the project-root `.github/scripts/notify-slack-build-result.sh` at the end of Android and iOS jobs with `if: always()`. The script reads `CI_SECRET_ROOT/shared/slack-webhook-url` or `SLACK_BUILD_WEBHOOK_URL`, skips when missing, and sends a short result message with one summary line plus profile, commit, and run URL. Optional mentions come from BuildCommit request `slackMentions`, serialized by the AutoBuild window as a JSON string array and passed to the script as `SLACK_BUILD_MENTIONS`. The AutoBuild UI stores shared rows in `BuildAutomationSettingsSO.buildCommitSlackMentions`, auto-created at `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`; each row has `enabled`, `memberId`, and `memo`, and only enabled member IDs enter the request. Legacy `BuildCommitSlackMentions` EditorPrefs data is migrated once into the SO when the SO list is empty, then removed from EditorPrefs.
- Workflow artifact paths must not hardcode a consuming project name. Android Google Play upload copies the discovered AAB to `.build/google-play-upload/upload.aab`, and iOS archive uses `Builds/iOSArchive/BuildCommit.xcarchive`.
- Android artifact upload is intentionally slim: upload AAB files from `.build/google-play-upload/*.aab` and `Builds/**/*.aab` with `compression-level: 0`, and upload logs as a separate artifact. Do not upload `Builds/**`, because Unity/Gradle intermediate output can contain hundreds of files and stall artifact upload.
- Android artifact/log upload steps are `continue-on-error: true` so GitHub artifact storage quota exhaustion does not mark an otherwise successful build and Google Play upload as failed.
- Google Play upload action input uses `tracks`, not deprecated `track`.
- iOS archive signing passes a single `CODE_SIGN_IDENTITY` value. Do not add `CODE_SIGN_IDENTITY[sdk=iphoneos*]` to the xcodebuild command; Xcode can misparse that command-line key and look for a certificate named `iphoneos*]=Apple Distribution...`.
- The Android and iOS workflows restore the Unity `Library` cache with `actions/cache/restore` only. Do not use the combined `actions/cache` save step in mobile deploy jobs, because cache post-save can hold or fail an otherwise successful upload.
- iOS artifact upload is intentionally slim: successful runs upload only IPA/plist files and logs, while failed runs upload diagnostic logs and export output. Do not upload `Builds/iOS/**` or the full `.xcarchive` by default; those directories can exceed 1 GB and make an otherwise successful TestFlight run fail during artifact upload.
- iOS app/diagnostic artifact upload steps are `continue-on-error: true` so GitHub artifact storage quota exhaustion does not mark an otherwise successful archive/export and TestFlight upload as failed.
- Runner setup files live under `RunnerSetup/`: `setup-local-runner-secrets.sh`, `validate-local-runner-secrets.sh`, `LOCAL_RUNNER_SECRETS_GUIDE.md`, and `AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md`.
- CI entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`.
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`.
- AutoBuild window workflow sync copies `WorkflowTemplates/buildcommit-auto-build.yml` to `.github/workflows/buildcommit-auto-build.yml` and package `.github/scripts/*.sh` workflow scripts to project `.github/scripts/`, including Slack notification support. Manual sync asks for confirmation; BuildCommit auto sync runs without confirmation when `Auto Sync Build Files` is enabled.
- Build Automation depends on `com.actionfit.buildsetting@1.1.3` or newer and `com.actionfit.githubauth@1.0.1` or newer. Do not add package-specific installer scripts for these dependencies. Keep dependency metadata in `package.json` and `Editor/PackageInfo/ActionFitPackageInfo_SO.asset` `_dependenciesOverride`; ActionFit Package Manager must publish that dependency metadata to the catalog CSV and write the resolved Git UPM URLs into `Packages/manifest.json` during install/update. If a dependency is missing, BuildAutomation should compile, show a clear warning, and stop the affected workflow.
- The storage commit alone should not trigger CI. The pushed `build/**` tag is the actual CI request.
- `Platform=Both` is split by the workflow into Android and iOS jobs before calling `CIBuildEntry`.

## Release Note Rules

- `ActionFitPackageInfo_SO.ReleaseNote` must contain only the single version being prepared.
- Do not copy older changelog entries into the newest release note.
- Version history and update-range summaries are composed by Custom Package Manager from separate catalog version rows.
- Do not add headings such as `## 1.0.0` inside ReleaseNote unless a specific package UI requires it; the catalog row already carries the version.

## Publish Notes

- Publishing is manual through Custom Package Manager.
- Do not manually add `com.actionfit.buildautomation` rows for unpublished versions to local or embedded package catalog CSV files before publish. Leave the catalog latest at the latest already-published version so `Publish Changed` can detect the new local `package.json` version; the user-run publish/catalog append flow must create the new catalog row after the package push and tag succeed.
- The `Build_Automation` GitHub repository must exist before first publish.
- Before reusing a version, check the remote Git tags. Published tags are immutable.
- Publish or catalog-register the required `com.actionfit.buildsetting` version before publishing a Build Automation version that depends on it.
- The package repository should include this `AI_GUIDE.md` so other projects can load the AI package context after installing the package.

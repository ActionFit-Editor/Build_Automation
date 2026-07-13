# AI Guide - Build Automation

This file is shipped inside the UPM package so an AI assistant in a consuming Unity project can understand the package without access to the source project's `Docs/AI` folder.

## Package Identity

- Package ID: `com.actionfit.buildautomation`
- Display name: Build Automation
- Repository: `https://github.com/ActionFit-Editor/Build_Automation.git`
- Current package version at generation time: `1.0.42`
- Unity version: `6000.2`

## Purpose

Build Automation owns BuildCommit request generation, Git tag based CI triggers, repository/Unity-project path resolution, request JSON parsing, Custom Symbols preparation, CI batchmode entry points, GitHub Actions workflow templates, local runner secret resolution, and macOS self-hosted mobile build guidance.

This package depends on `com.actionfit.buildsetting`, `com.actionfit.customsymbols`, and `com.actionfit.githubauth` (AI GitHub). Keep build/player settings in Build Setting and build symbol selection in Custom Symbols. Keep CI request orchestration and remote build workflow behavior in Build Automation.

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
- Read `Packages/com.actionfit.customsymbols/AI_GUIDE.md` before changing `CustomSymbolsSO.GetBuildSymbols(BuildTarget)` integration or automatic build symbol behavior.
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

- Menu: `Tools/Package/Build Automation/AutoBuild`.
- Build request path: Git repository root `.build/build_request.json`, never the nested Unity project root.
- Current BuildRequest schema is 11. It adds repository-relative `unityProjectPath` and `autoConfigureBuildSymbols`. Both earlier and later schemas are rejected; recreate an old request from the AutoBuild window.
- `BuildAutomationProjectPaths` resolves the Git repository root with `git rev-parse --show-toplevel`. `unityProjectPath` is `.` for a root project or a normalized path such as `KnitFactory` for a nested project. Absolute paths, `..`, control characters, and paths escaping the repository must be rejected.
- Build tag prefix: `build/**`.
- Storage commit message prefix: `[BuildRequest]`.
- Distribution profile request field: `distributionProfile`. Current profiles are `Actionfit` and `Stormborn`; only the profile name is stored in request JSON.
- BuildCommit window starts with `Platform=None`. `Commit, Tag & Push` is disabled until the user selects `Current`, `Android`, `iOS`, or `Both`. `Current` remains a selectable option and resolves to the active Unity build target when the request is created.
- BuildCommit window wraps its main body in a vertical scroll view so short Unity editor windows can still reach settings, actions, and logs. Keep the log area as a nested scroll view with bounded layout behavior.
- `Commit, Tag & Push` runs local `git push` and tag push from the Unity editor. Each developer machine that uses BuildCommit must have GitHub credentials configured for the consuming repository with push/tag permission. BuildCommit uses `GitHubAuthPreflight.EnsureProjectGitHubPushAccess` from `com.actionfit.githubauth` before creating the request commit/tag; on failure, AI GitHub shows the shared authentication-required dialog and BuildCommit stops. BuildAutomation must not hard-reference `ActionFit.BuildSetting.Editor` or `ActionFit.GitHubAuth.Editor` in `using` statements or the editor asmdef, because missing Git UPM dependencies would prevent the package from compiling. Use `BuildSettingBridge` and reflection for optional calls. Leave dependency installation to ActionFit Package Manager's catalog CSV dependency flow; if editing `Packages/manifest.json` manually, all required Git UPM URLs must be added explicitly.
- All Build Automation Git subprocesses must use `GitProcessRunner`, which starts concurrent stdout/stderr drains before waiting for process exit. Keep the five-minute timeout and process-tree termination so warning-heavy commands such as `git add .` cannot deadlock the Unity editor indefinitely. Never delete `.git/index.lock` while the owning Git process is still running.
- When explaining or diagnosing local BuildCommit push failures, route detailed command sequences and error-specific guidance through `Packages/com.actionfit.githubauth/README.md` and `Packages/com.actionfit.githubauth/AI_GUIDE.md`. Treat `fatal: could not read Username for 'https://github.com': Device not configured` as a local GitHub credential/helper issue, not a workflow yml or GitHub Actions runner issue.
- BuildCommit window has `Auto Sync Build Files`, stored in `EditorPrefs` as `BuildCommitAutoSyncWorkflowAssets`, defaulting to true. When enabled, `Commit, Tag & Push` syncs package workflow assets into the Git repository root `.github/` before saving the request and running `git add .`.
- Keep the internal `BuildSettingBridge` type in a source file that Unity already includes in `com.actionfit.buildautomation.Editor` unless a Unity compile validation confirms a newly added bridge file appears in `CompilationPipeline.GetAssemblies()` source files. This avoids partial package/source-list refresh states where `BuildCommitWindow`, `BuildRequestUtility`, and `CIBuildEntry` compile but the bridge source file is omitted, causing `CS0103: BuildSettingBridge`.
- Android requests serialize `androidKeystoreFileName`, `androidKeystoreBase64`, `androidKeystorePassword`, `androidAliasPassword`, and `androidKeyaliasName` from Build Setting. Request values take precedence; runner-provided `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, and `ANDROID_KEYALIAS_PASS` are fallbacks when the corresponding request values are empty.
- BuildCommit window platform changes reset default request options: Android uses `AndroidAab` and `GooglePlayInternal`; iOS uses `iOSXcodeProject` and `TestFlight`; Both uses `AndroidAabAndiOSXcodeProject` and `GooglePlayInternalAndTestFlight`.
- App identifier request fields: `androidPackageName`, copied from `BuildSettingsSO.androidPackageName`, and `iosBundleId`, copied from `BuildSettingsSO.iosPackageName`. The workflow uses these request values for Google Play `packageName` and TestFlight `app_identifier`.
- `.build/build_request.json` intentionally carries the project-specific Android keystore bytes and signing passwords. Do not log these values. Per-job request preparation must preserve the four Android signing fields while continuing to remove unsupported legacy iOS/upload credential-shaped fields.
- The Mac runner local secret bundle selected by `CI_SECRET_ROOT` remains authoritative for Google Play, iOS, App Store Connect, certificate, provisioning profile, keychain, and Slack credentials. The workflow template pins `CI_SECRET_ROOT` to `/Users/lydia/workspace/build-automation` for the existing ActionFit self-hosted runners, while scripts invoked without that environment variable default to `$HOME/ci-secrets/build-automation`. Android signing values in the bundle are optional fallbacks for requests that omit one or more Android signing fields. BuildCommit requests must not carry runner-local paths.
- Workflow project resolution calls repository-root `.github/scripts/resolve-unity-project.sh` before Unity-dependent steps. It validates `unityProjectPath` and exports `UNITY_PROJECT_DIR`, manifest/version/cache/build/log paths, and repository-root request/upload paths. `resolve-unity-editor.sh` reads `$UNITY_PROJECT_VERSION_FILE` and fails early if that editor is not installed under `UNITY_HUB_EDITOR_ROOT`.
- Workflow secret validation calls repository-root `.github/scripts/validate-local-runner-secrets.sh`. The package keeps source copies under `.github/scripts/`, and the AutoBuild workflow sync button copies them into the repository together with the workflow yml. Emit GitHub `::add-mask::` commands only when `GITHUB_ACTIONS=true`; local validation must never print credential values. Shell regression fixtures must set `GITHUB_ACTIONS=false` for local cases and `GITHUB_ACTIONS=true` for the explicit Actions masking case so a parent runner environment cannot change test semantics. Do not make pre-Unity shell steps depend on package import or `Library/PackageCache`.
- Workflow private package access preparation calls repository-root `.github/scripts/prepare-actionfit-private-package-access.sh` before Unity starts. It configures GitHub HTTPS access from runner `gh auth` or from `CI_SECRET_ROOT/shared/github-package-read-token`, rewrites GitHub SSH package URLs to HTTPS, and preflights ActionFit GitHub package repositories listed in `$UNITY_MANIFEST_PATH`. When the local token helper path is used, the script clears generic `credential.helper`, configures the GitHub-host scoped helper, and exports matching `GIT_CONFIG_*` values into `GITHUB_ENV` so later workflow steps and Unity child Git processes keep using the same private package credential.
- Workflow Slack notification calls repository-root `.github/scripts/notify-slack-build-result.sh` at the start of each Android/iOS job and again at the end with `if: always()`. Start calls pass `BUILD_JOB_STATUS=start` and send a `[Start]` summary. Result calls pass `BUILD_STARTED_AT_EPOCH` so the script can add a `Time: ...` line to the result message. The script reads `CI_SECRET_ROOT/shared/slack-webhook-url` or `SLACK_BUILD_WEBHOOK_URL`, skips when missing, and sends a short message with one summary line plus time when available, profile, commit, and run URL. Optional mentions come from BuildCommit request `slackMentions`, serialized by the AutoBuild window as a JSON string array and passed to the script as `SLACK_BUILD_MENTIONS`. The AutoBuild UI stores shared rows in `BuildAutomationSettingsSO.buildCommitSlackMentions`, auto-created at `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`; each row has `enabled`, `memberId`, and `memo`, and only enabled member IDs enter the request. Legacy `BuildCommitSlackMentions` EditorPrefs data is migrated once into the SO when the SO list is empty, then removed from EditorPrefs.
- Workflow artifact paths must not hardcode a consuming project name. Unity outputs live under `$UNITY_BUILD_DIR`; Android Google Play upload copies the discovered AAB to repository-root `.build/google-play-upload/upload.aab`, and iOS archive uses `$IOS_ARCHIVE_PATH`.
- Android and iOS Unity batchmode build steps must capture the Unity exit status, print the last 400 lines of `Logs/unity-android.log` or `Logs/unity-ios.log` inside a GitHub Actions log group on failure, then exit with the original Unity status. This keeps failed BuildCommit runs diagnosable from the Actions page without downloading artifacts.
- Android artifact upload is intentionally slim: upload the prepared repository-root AAB and discovered files under `$UNITY_BUILD_DIR` with `compression-level: 0`, and upload `$UNITY_LOG_DIR` separately. Do not upload the complete build directory because Unity/Gradle intermediate output can contain hundreds of files and stall artifact upload.
- Android artifact/log upload steps are `continue-on-error: true` so GitHub artifact storage quota exhaustion does not mark an otherwise successful build and Google Play upload as failed.
- Any artifact step that reads `steps.paths.outputs` must be guarded by a successful path-resolution outcome. Android `always()` uploads also require `steps.paths.outcome == 'success'`; failed iOS diagnostics require the same guard so an early resolve failure never expands unresolved paths.
- Google Play upload action input uses `tracks`, not deprecated `track`.
- iOS archive signing passes a single `CODE_SIGN_IDENTITY` value. Do not add `CODE_SIGN_IDENTITY[sdk=iphoneos*]` to the xcodebuild command; Xcode can misparse that command-line key and look for a certificate named `iphoneos*]=Apple Distribution...`.
- The Android and iOS workflows restore the Unity `Library` cache with `actions/cache/restore` only. Do not use the combined `actions/cache` save step in mobile deploy jobs, because cache post-save can hold or fail an otherwise successful upload.
- iOS artifact upload is intentionally slim: successful runs upload only IPA/plist files and logs from resolved project paths, while failed runs upload diagnostic logs and export output. Do not upload the full Xcode project or `.xcarchive` by default; those directories can exceed 1 GB and make an otherwise successful TestFlight run fail during artifact upload.
- iOS app/diagnostic artifact upload steps are `continue-on-error: true` so GitHub artifact storage quota exhaustion does not mark an otherwise successful archive/export and TestFlight upload as failed.
- Runner setup files live under `RunnerSetup/`: `setup-local-runner-secrets.sh`, `validate-local-runner-secrets.sh`, `LOCAL_RUNNER_SECRETS_GUIDE.md`, and `AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md`.
- CI build entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`.
- CI target switch entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.SwitchToRequestBuildTarget`.
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`.
- AutoBuild window workflow sync copies `WorkflowTemplates/buildcommit-auto-build.yml` to Git repository root `.github/workflows/buildcommit-auto-build.yml` and package `.github/scripts/*.sh` workflow scripts to repository root `.github/scripts/`. Manual sync asks for confirmation; BuildCommit auto sync runs without confirmation when `Auto Sync Build Files` is enabled.
- `BuildAutomationSettingsSO.autoConfigureBuildSymbols` defaults to true and is serialized as request `autoConfigureBuildSymbols`. When enabled, the reflection bridge calls `CustomSymbolsSO.FindOrCreateSettingsAsset()` before obtaining `GetBuildSymbols(BuildTarget)`. Custom Symbols 1.0.6 creates a missing default asset from current Standalone/Android/iOS defines; creation failure or a later symbol mismatch fails the build. `SwitchToRequestBuildTarget` writes scripting define symbols and the separate `BuildFromRequest` process validates exact symbol-set equality. Disabled requests skip apply/validation.
- Build Automation depends on `com.actionfit.buildsetting@1.1.9`, `com.actionfit.customsymbols@1.0.6`, and `com.actionfit.githubauth@1.0.6` or newer. Keep dependency metadata in `package.json` and `Editor/PackageInfo/ActionFitPackageInfo_SO.asset` `_dependenciesOverride`; ActionFit Package Manager must publish that dependency metadata to the catalog CSV and write the resolved Git UPM URLs into the Unity project's `Packages/manifest.json` during install/update. If a dependency is missing, BuildAutomation should compile, show a clear warning, and stop the affected workflow.
- The storage commit alone should not trigger CI. The pushed `build/**` tag is the actual CI request.
- Android and iOS workflow jobs must run `CIBuildEntry.SwitchToRequestBuildTarget` in a separate Unity batchmode process before `CIBuildEntry.BuildFromRequest`. This lets Unity reopen/recompile editor assemblies for the requested platform so Build Setting's `UNITY_ANDROID` or `UNITY_IOS` build process exists before the actual build call.
- `Platform=Both` is split by the workflow into Android and iOS jobs before calling `CIBuildEntry`.

## Package Tools Menu

- Unity menu root: `Tools/Package/Build Automation/`.
- Keep package commands under this package root.
- Lower separated entries:
- `Setting SO`: focuses this package's settings ScriptableObject.
- `README`: opens this package README.
- Do not add README or Setting SO access back to Custom Package Manager package rows or Project Files.

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
- Publish or catalog-register the required `com.actionfit.buildsetting` and `com.actionfit.customsymbols` versions before publishing a Build Automation version that depends on them.
- The package repository should include this `AI_GUIDE.md` so other projects can load the AI package context after installing the package.

# AI Guide - Build Automation

This file is shipped inside the UPM package so an AI assistant in a consuming Unity project can understand the package without access to the source project's `Docs/AI` folder.

## Package Identity

- Package ID: `com.actionfit.buildautomation`
- Display name: Build Automation
- Repository: `https://github.com/ActionFit-Editor/Build_Automation.git`
- Current package version at generation time: `1.0.61`
- Unity version: `6000.2`

## Purpose

### Settings SO Lifecycle

- `BuildAutomationSettingsSO` is registered as `EditorOnly` with canonical path `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`.
- The shared provider preserves the remembered EditorPrefs asset, canonical asset, or one unique existing project asset before guarded creation; duplicates block creation.
- This package directly depends on `com.actionfit.sosingleton@1.0.6` and keeps settings resolution in its Editor assembly.

Build Automation owns BuildCommit request generation, Git tag based CI triggers, repository/Unity-project path resolution, request JSON parsing, Custom Symbols preparation, CI batchmode entry points, GitHub Actions workflow templates, local runner secret resolution, and macOS self-hosted mobile build guidance.

This package depends on `com.actionfit.buildsetting`, `com.actionfit.customsymbols`, and `com.actionfit.githubauth` (AI GitHub). Keep build/player settings in Build Setting and build symbol selection in Custom Symbols. Keep CI request orchestration and remote build workflow behavior in Build Automation.

## Agent Skills

- `Skills~/manifest.json` registers schema v2 `mobile-build-help` and `mobile-build-preflight` for Codex and Claude.
- Both skills are read-only. Preflight inspects dependency versions, project paths, workflow synchronization state, settings-asset presence, and an allowlisted subset of an existing BuildRequest.
- The skills never print signing or credential values and do not create BuildRequests, sync workflows, change settings, commit, tag, push, build, upload, or deploy.

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
- Treat `WorkflowTemplates/*.yml`, package `.github/actions/*/action.yml`, package-managed `.github` scripts, runner setup guides, package README/AI guide updates, and package metadata changes as package source changes. Prepare a package release and bump `package.json` version when these files change; the consuming project's root `.github/` files are only synced project copies.
- Keep Android/iOS player/build settings and local build process implementations in `com.actionfit.buildsetting`.
- Do not change public menu paths, request JSON field names, enum numeric values, tag prefix, or CI entry method casually. Existing workflow triggers and stored request JSON depend on them.
- Preserve Unity `.meta` files when adding, moving, or renaming files inside the package.
- When behavior changes, update this `AI_GUIDE.md` and `README.md` before publishing so consuming projects receive the latest AI context.

## Behavior Notes

- Menu: `Tools/Package/Build Automation/AutoBuild`.
- Build request path: Git repository root `.build/build_request.json`, never the nested Unity project root.
- The committed `.build/build_request.json` is read-only during CI. `PrepareBuildSequence` writes allowlisted Android/iOS copies under repository-root `.build/ci/`; `BuildRequestUtility.Load` accepts only the original path or those fixed copies and rejects path escape, alternate names, and symbolic-link traversal.
- Current BuildRequest schema is 12. It carries repository-relative `unityProjectPath`, `autoConfigureBuildSymbols`, and the default-off `developmentBuild` snapshot. Both earlier and later schemas are rejected; recreate an old request from the AutoBuild window.
- `BuildAutomationProjectPaths` resolves the Git repository root with `git rev-parse --show-toplevel`. `unityProjectPath` is `.` for a root project or a normalized path such as `KnitFactory` for a nested project. Absolute paths, `..`, control characters, and paths escaping the repository must be rejected.
- Build tag prefix: `build/**`.
- Storage commit message prefix: `[BuildRequest]`.
- Distribution profile request field: `distributionProfile`. Current profiles are `Actionfit` and `Stormborn`; only the profile name is stored in request JSON.
- BuildCommit window starts with `Platform=None`. `Commit, Tag & Push` is disabled until the user selects `Current`, `Android`, `iOS`, or `Both`. `Current` remains a selectable option and resolves to the active Unity build target when the request is created.
- BuildCommit window wraps its main body in a vertical scroll view so short Unity editor windows can still reach settings, actions, and logs. Keep the log area as a nested scroll view with bounded layout behavior.
- `Commit, Tag & Push` runs local `git push` and tag push from the Unity editor. Each developer machine that uses BuildCommit must have GitHub credentials configured for the consuming repository with push/tag permission. BuildCommit uses `GitHubAuthPreflight.EnsureProjectGitHubPushAccess` from `com.actionfit.githubauth` before creating the request commit/tag; on failure, AI GitHub shows the shared authentication-required dialog and BuildCommit stops. BuildAutomation must not hard-reference `ActionFit.BuildSetting.Editor` or `ActionFit.GitHubAuth.Editor` in `using` statements or the editor asmdef, because missing Git UPM dependencies would prevent the package from compiling. Use `BuildSettingBridge` and reflection for optional calls. Leave dependency installation to ActionFit Package Manager's catalog CSV dependency flow; if editing `Packages/manifest.json` manually, all required Git UPM URLs must be added explicitly.
- All Build Automation Git subprocesses must use `GitProcessRunner`, which starts concurrent stdout/stderr drains before waiting for process exit. Keep the five-minute timeout and process-tree termination so warning-heavy commands such as `git add .` cannot deadlock the Unity editor indefinitely. BuildCommit commands retry only the exact transient `index.lock` contention signature up to 20 times at 250 ms intervals; persistent contention still fails with the original Git error. Never delete `.git/index.lock` while the owning Git process is still running.
- When explaining or diagnosing local BuildCommit push failures, route detailed command sequences and error-specific guidance through `Packages/com.actionfit.githubauth/README.md` and `Packages/com.actionfit.githubauth/AI_GUIDE.md`. Treat `fatal: could not read Username for 'https://github.com': Device not configured` as a local GitHub credential/helper issue, not a workflow yml or GitHub Actions runner issue.
- BuildCommit window has `Auto Sync Build Files`, stored in `EditorPrefs` as `BuildCommitAutoSyncWorkflowAssets`, defaulting to true. When enabled, `Commit, Tag & Push` syncs package workflow assets into the Git repository root `.github/` before saving the request and running `git add .`.
- Keep the internal `BuildSettingBridge` type in a source file that Unity already includes in `com.actionfit.buildautomation.Editor` unless a Unity compile validation confirms a newly added bridge file appears in `CompilationPipeline.GetAssemblies()` source files. This avoids partial package/source-list refresh states where `BuildCommitWindow`, `BuildRequestUtility`, and `CIBuildEntry` compile but the bridge source file is omitted, causing `CS0103: BuildSettingBridge`.
- Android requests serialize `androidKeystoreFileName`, `androidKeystoreBase64`, `androidKeystorePassword`, `androidAliasPassword`, and `androidKeyaliasName` from Build Setting. Request values take precedence; runner-provided `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASS`, and `ANDROID_KEYALIAS_PASS` are fallbacks when the corresponding request values are empty.
- BuildCommit window platform changes reset default request options: Android uses `AndroidAab` and `GooglePlayInternal`; iOS uses `iOSXcodeProject` and `TestFlight`; Both uses `AndroidAabAndiOSXcodeProject` and `GooglePlayInternalAndTestFlight`.
- App identifier request fields: `androidPackageName`, copied from `BuildSettingsSO.androidPackageName`, and `iosBundleId`, copied from `BuildSettingsSO.iosPackageName`. The workflow uses these request values for Google Play `packageName` and TestFlight `app_identifier`.
- `.build/build_request.json` intentionally carries the project-specific Android keystore bytes and signing passwords. Do not log these values or overwrite the original request in CI. The Android working copy preserves Android signing fields and removes iOS-only values; the iOS working copy removes Android signing values.
- The shared Unity runner bundle selected by `CI_SECRET_ROOT` is authoritative for Google Play, iOS, App Store Connect, certificate, provisioning profile, keychain, and Slack credentials. `resolve-local-secret-root.sh` prefers the runner environment, then checks the Mac Studio local path, the MacBook SMB mount `/Volumes/ActionFitBuildAutomation`, and the legacy home fallback. Production runners should set a stable per-host root and mount SMB before the runner service starts. Android signing values in the bundle are optional fallbacks for requests that omit one or more Android signing fields. BuildCommit requests must not carry runner-local paths or credentials.
- Workflow project resolution calls repository-root `.github/scripts/resolve-unity-project.sh` before Unity-dependent steps. It validates `unityProjectPath` and exports `UNITY_PROJECT_DIR`, manifest/version/cache/build/log paths, and repository-root request/upload paths. `resolve-unity-editor.sh` reads `$UNITY_PROJECT_VERSION_FILE` and fails early if that editor is not installed under `UNITY_HUB_EDITOR_ROOT`.
- Workflow secret validation calls repository-root `.github/scripts/validate-local-runner-secrets.sh`. The package keeps source copies under `.github/scripts/`, and the AutoBuild workflow sync button copies them into the repository together with the workflow yml. Emit GitHub `::add-mask::` commands only when `GITHUB_ACTIONS=true`; local validation must never print credential values. Shell regression fixtures must set `GITHUB_ACTIONS=false` for local cases and `GITHUB_ACTIONS=true` for the explicit Actions masking case so a parent runner environment cannot change test semantics. Do not make pre-Unity shell steps depend on package import or `Library/PackageCache`.
- Workflow private package access preparation calls repository-root `.github/scripts/prepare-actionfit-private-package-access.sh` before Unity starts. It configures GitHub HTTPS access from runner `gh auth` or from `CI_SECRET_ROOT/shared/github-package-read-token`, rewrites GitHub SSH package URLs to HTTPS, and preflights ActionFit GitHub package repositories listed in `$UNITY_MANIFEST_PATH`. When the local token helper path is used, the script clears generic `credential.helper`, configures the GitHub-host scoped helper, and exports matching `GIT_CONFIG_*` values into `GITHUB_ENV` so later workflow steps and Unity child Git processes keep using the same private package credential.
- Slack notification and Development APK delivery run inside the trusted affinity `mobile-build` job using repository-synchronized helpers. Send advisory start, failure, and non-APK result messages through the same Bot `chat.postMessage` destination used by Development APK uploads. Expose the phase-marker-validated APK path from the Android composite, but wait until all requested platform actions and deferred Store uploads have succeeded before uploading that local file directly through Slack's external upload APIs. The APK post carries the success comment, so suppress a duplicate success message. Missing credentials, an unreadable APK, timeout, or Slack rejection must produce `BUILD SUCCESS / APK DELIVERY FAILED` when possible without changing a successful source build conclusion.
- Current Slack credentials live at `CI_SECRET_ROOT/shared/{slack-bot-token,slack-channel-id}` and must never enter GitHub Secrets, BuildRequest, or logs. The Bot requires `chat:write`, `files:write`, and target-channel membership. A legacy `slack-webhook-url` file may remain for older package versions, but current helpers must not read or use it. Direct Slack calls require bounded API/file-transfer timeouts. Persist a repository/run-id keyed pending/delivered receipt under shared `state/slack-apk-delivery`; never persist tokens, upload URLs, or APK paths. Discard only pre-completion pending state automatically. Preserve armed pending state after an indeterminate completion, suppress contradictory Slack failure posts, and require operator reconciliation before retry. Never include pending receipts in automatic age/LRU cleanup. Only trusted `unity-mobile` workflows may access this bundle; `ci`, package-validation, allocator, and untrusted pull request workflows must not run on those runners.
- Optional mentions still come from BuildCommit request `slackMentions`, serialized by the AutoBuild window as a JSON string array. The AutoBuild UI stores shared rows in `BuildAutomationSettingsSO.buildCommitSlackMentions`, auto-created at `Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset`; each row has `enabled`, `memberId`, and `memo`, and only enabled member IDs enter the request. Legacy `BuildCommitSlackMentions` EditorPrefs data is migrated once into the SO when the SO list is empty, then removed from EditorPrefs.
- Workflow artifact paths must not hardcode a consuming project name. Unity outputs live under `$UNITY_BUILD_DIR`; Android Google Play upload copies the discovered AAB to repository-root `.build/google-play-upload/upload.aab`, and iOS archive uses `$IOS_ARCHIVE_PATH`.
- Android and iOS Unity batchmode build steps must capture the Unity exit status, print the last 400 lines of `Logs/unity-android.log` or `Logs/unity-ios.log` inside a GitHub Actions log group on failure, then exit with the original Unity status. This keeps failed BuildCommit runs diagnosable from the Actions page without downloading artifacts.
- Android artifact upload is intentionally slim: a successful Store upload does not retain a duplicate AAB. Store failures or non-Store AAB builds retain only phase-marker-validated files copied into the transient staging directory for 3 days with `compression-level: 0`; never scan the preserved affinity build directory for recovery files. iOS uses the exact TestFlight upload step outcome and fresh IPA output. Recovery binary uploads are required and must expose quota or transport failure. Clear `UNITY_LOG_DIR` once per approved workflow run so seven-day diagnostics never mix old affinity logs. Development APKs are never relayed through GitHub Artifact; upload them directly from the fresh local output. Do not upload the complete build directory because Unity/Gradle intermediate output can contain hundreds of files and stall artifact upload.
- Because ignored build outputs survive the cache-preserving checkout, Android AAB discovery must require a file newer than the current phase marker. iOS must clear only its fixed Xcode/archive/export transient paths before rebuilding. Do not delete the versioned build-retention root or `Library` as a general workspace reset.
- Android artifact/log upload steps are `continue-on-error: true` so GitHub artifact storage quota exhaustion does not mark an otherwise successful build and Google Play upload as failed.
- Composite action artifact paths come from the environment exported by the successful repository-root path-resolution step. Platform actions must not run before that step succeeds.
- Google Play upload action input uses `tracks`, not deprecated `track`.
- iOS archive signing passes a single `CODE_SIGN_IDENTITY` value. Do not add `CODE_SIGN_IDENTITY[sdk=iphoneos*]` to the xcodebuild command; Xcode can misparse that command-line key and look for a certificate named `iphoneos*]=Apple Distribution...`.
- The affinity runner's local Unity `Library` is authoritative and survives pre-checkout reset plus `actions/checkout` with `clean: false`. Use `actions/cache/restore` only as a cold fallback when `Library/SourceAssetDB` is absent. Do not add a remote cache save step because cache post-save can hold or fail an otherwise successful upload.
- iOS artifact upload is intentionally slim: a successful TestFlight upload does not retain a duplicate IPA. TestFlight failures or non-Store IPA builds retain IPA/plist files for 3 days, while failure diagnostics retain logs and export options for 7 days without duplicating the IPA. Do not upload the full Xcode project or `.xcarchive` by default; those directories can exceed 1 GB and make an otherwise successful TestFlight run fail during artifact upload.
- iOS app/diagnostic artifact upload steps are `continue-on-error: true` so GitHub artifact storage quota exhaustion does not mark an otherwise successful archive/export and TestFlight upload as failed.
- Runner setup files live under `RunnerSetup/`: `setup-local-runner-secrets.sh`, `validate-local-runner-secrets.sh`, `LOCAL_RUNNER_SECRETS_GUIDE.md`, and `AI_MAC_STUDIO_BUILD_AUTOMATION_GUIDE.md`.
- CI build entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`.
- CI target switch entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.SwitchToRequestBuildTarget`.
- CI sequence entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.PrepareBuildSequence`.
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`.
- AutoBuild window workflow sync copies the workflow template, `.github/actions/build-android/action.yml`, `.github/actions/build-ios/action.yml`, allocator `.github/scripts/allocate-unity-mobile-runner.js`, the shared-root resolver, Slack helpers, and other managed build scripts declared by `BuildCommitWorkflowSyncUtility` into the Git repository root `.github/`. Manual sync asks for confirmation; BuildCommit auto sync runs without confirmation when `Auto Sync Build Files` is enabled. Sync also removes the obsolete repository `buildcommit-slack-delivery.yml`.
- `BuildAutomationSettingsSO.autoConfigureBuildSymbols` defaults to true and is serialized as request `autoConfigureBuildSymbols`. When enabled, the reflection bridge calls `CustomSymbolsSO.FindOrCreateSettingsAsset()` before obtaining `GetBuildSymbols(BuildTarget)`. Custom Symbols 1.0.6 creates a missing default asset from current Standalone/Android/iOS defines; creation failure or a later symbol mismatch fails the build. `SwitchToRequestBuildTarget` writes scripting define symbols and the separate `BuildFromRequest` process validates exact symbol-set equality. Disabled requests skip apply/validation.
- `BuildSettingsSO.developmentBuild` is shown in AutoBuild regardless of Custom Symbols and serialized into each schema 12 request. `CIBuildEntry` applies it before the actual platform build and fails fast when the reflection bridge cannot find the required public bool field. Development Android working requests force `AndroidApk` and `None` upload and expose only an APK newer than the current phase marker. After all requested builds and deferred Store uploads succeed, the top-level job uploads that exact local APK directly to Slack. The APK post contains the success comment, direct delivery failure is advisory, and no Development APK GitHub Artifact is created. Development iOS working requests preserve the marketing version, force TestFlight, and start bundle numbering at `1`. Before Unity builds the Xcode project, `check-testflight-build-number.rb` reads every completed build and active upload for that marketing version through the official App Store Connect `apps`, `builds`, and `buildUploads` APIs, follows bounded same-origin pagination, and selects `max(1, occupied maximum + 1)`. The composite action atomically writes only that resolved number to `.build/ci/build_request_ios.json`, so the generated app receives the same `CFBundleVersion`; the original request and `BuildSettingsSO` remain unchanged. Development success notifications include `iOS TestFlight: v<marketing-version>(<effective-build-number>)` after a successful iOS upload, including the APK attachment comment used by Both requests and the advisory APK-delivery-failure message. Failed builds must not claim that an iOS version was uploaded. The resolver generates a bounded ES256 JWT from the runner-local API key, keeps it out of process arguments, retries transient curl failures, and fails closed on authentication, transport, non-integer build numbers, unsafe pagination, or response-contract errors. Release working-request behavior remains unchanged. Keep Development Build independent from legacy `isDevMode` and the `DEV` scripting define.
- Sharing one credential bundle means every trusted `unity-mobile` runner process can read Slack and Store credentials. Keep `ci`, validation, allocator, and untrusted pull request workflows off those runners.
- Build Automation depends on `com.actionfit.buildsetting@1.1.13`, `com.actionfit.customsymbols@1.0.9`, and `com.actionfit.githubauth@1.0.9` or newer. Keep dependency metadata in `package.json` and `Editor/PackageInfo/ActionFitPackageInfo_SO.asset` `_dependenciesOverride`; ActionFit Package Manager must publish that dependency metadata to the catalog CSV and write the resolved Git UPM URLs into the Unity project's `Packages/manifest.json` during install/update. If a dependency is missing, BuildAutomation should compile, show a clear warning, and stop the affected workflow.
- The storage commit alone should not trigger CI. The pushed `build/**` tag is the actual CI request.
- The workflow runs `allocate` on the dedicated `mobile-build-allocator` runner group with the `runner-allocator` label before mobile scheduling. It must not check out repository content. It calls the fixed host-local `/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner` executable with `GITHUB_REPOSITORY` and `GITHUB_OUTPUT`.
- The allocator uses repository variable `UNITY_RUNNER_AFFINITY_LABEL` when set; otherwise it derives `project-<repository-slug>`. The value must match `project-[a-z0-9-]+`. A host-local file lock serializes organization-wide assignments. It reuses one existing online mapping or assigns the label to the online eligible runner with the fewest `project-*` labels, using idle state as a tie-breaker rather than rejecting busy runners. Eligible runners require `unity-mobile` and must not have `ci`, `ci-validation`, `unity-package-ci`, or `runner-allocator`.
- Organization runner API access comes from the allocator Mac user's existing `gh` Keychain authentication. The workflow does not use `UNITY_RUNNER_ALLOCATOR_TOKEN`. Missing allocator runner access, executable, authentication, duplicate mappings, offline mapped runners, or an empty candidate pool must fail in `allocate` before `mobile-build` is queued.
- `mobile-build` depends on `allocate` and requests `self-hosted`, `macOS`, `unity-mobile`, and `${{ needs.allocate.outputs.affinity_label }}` so both platforms use the same runner-local workspace.
- Before reset and checkout, `mobile-build` verifies that `RUNNER_NAME` matches the allocator output and atomically refreshes `.unity-mobile-affinity.json` in the workspace parent. The host cleanup process uses this marker for the longer affinity retention policy even when a later checkout or build step fails.
- `PrepareBuildSequence` chooses the active Android/iOS target first, defaults to Android when neither mobile target is active, writes platform working requests, and prepares the first target in one Unity process. The first `BuildFromRequest` runs in a separate process. A Both request then runs `SwitchToRequestBuildTarget` for the second platform in another process before its separate `BuildFromRequest`, limiting a normal Both build to one platform switch.
- For Both requests, the first platform composite starts its Store upload through `store-upload-worker.rb` after copying immutable IPA/AAB upload inputs, then returns so the second target switch/build can overlap that network transfer. The workflow waits for the first upload after the second platform action, uploads deferred artifacts and diagnostics, then cleans credentials and worker state. Never delete or overwrite the first IPA/AAB, mapping, native symbols, or Store credential before the deferred upload is terminal.
- Android deferred upload uses `upload-google-play.sh` with Fastlane `supply`, preserving the internal/completed release, mapping.txt, and native debug symbols behavior of the synchronous Google Play action. Single-platform and second-platform Android uploads remain synchronous.
- All TestFlight uploads use `upload-testflight.rb`. Each `pilot` attempt runs in a fresh TMPDIR and process group with a default 900-second hard timeout, at most two attempts, and a ten-second retry delay. Timeout or cancellation must terminate the complete pilot/altool process group; do not replace this with an unbounded Fastlane invocation.
- Android/iOS composite action invocations use `continue-on-error` at the job boundary so a failed first platform or deferred Store upload does not skip the second. The final aggregation step fails the job when any requested platform action, deferred upload finalizer, or worker cleanup failed. Keep the deferred worker capped at 3600 seconds and the complete mobile job capped at 220 minutes so the advisory 30-minute Slack transfer still has headroom after the 180-minute build budget.
- Each composite action narrows `GooglePlayInternalAndTestFlight` to its own store target before local-secret validation. This prevents iOS signing/keychain environment from becoming an Android phase prerequisite, or Google Play credentials from becoming an iOS phase prerequisite, now that both phases share one job environment.

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

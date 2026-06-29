# AI Guide - Build Automation

This file is shipped inside the UPM package so an AI assistant in a consuming Unity project can understand the package without access to the source project's `Docs/AI` folder.

## Package Identity

- Package ID: `com.actionfit.buildautomation`
- Display name: Build Automation
- Repository: `https://github.com/ActionFit-Editor/Build_Automation.git`
- Current package version at generation time: `1.0.7`
- Unity version: `6000.2`

## Purpose

Build Automation owns BuildCommit request generation, Git tag based CI triggers, request JSON parsing, CI batchmode entry points, GitHub Actions workflow templates, and macOS self-hosted mobile build guidance.

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

## Editing Rules

- Keep BuildCommit, request JSON, CI entry, workflow template, and runner setup changes in this package.
- Keep Android/iOS player/build settings and local build process implementations in `com.actionfit.buildsetting`.
- Do not change public menu paths, request JSON field names, enum numeric values, tag prefix, or CI entry method casually. Existing workflow triggers and stored request JSON depend on them.
- Preserve Unity `.meta` files when adding, moving, or renaming files inside the package.
- When behavior changes, update this `AI_GUIDE.md` and `README.md` before publishing so consuming projects receive the latest AI context.

## Behavior Notes

- Menu: `Tools/ActionFit/Build Commit`.
- Build request path: `.build/build_request.json`.
- Build tag prefix: `build/**`.
- Storage commit message prefix: `[BuildRequest]`.
- Distribution profile request field: `distributionProfile`. Current profiles are `Actionfit` and `Stormborn`; only the profile name is stored in request JSON.
- Android request alias field: `androidKeyaliasName`, copied from `BuildSettingsSO.keyStoreAlias`. Default production signing should still use GitHub Actions Secrets.
- BuildCommit window platform changes reset default request options: Android uses `AndroidAab` and `GooglePlayInternal`; iOS uses `iOSXcodeProject` and `TestFlight`; Both uses `AndroidAabAndiOSXcodeProject` and `GooglePlayInternalAndTestFlight`.
- App identifier request fields: `androidPackageName`, copied from `BuildSettingsSO.androidPackageName`, and `iosBundleId`, copied from `BuildSettingsSO.iosPackageName`. The workflow uses these request values for Google Play `packageName` and TestFlight `app_identifier`.
- Experimental secret override request fields: `androidKeystorePassword`, `androidAliasPassword`, `googlePlayServiceAccountJson`, `appStoreConnectApiKeyId`, `appStoreConnectIssuerId`, `appStoreConnectApiKeyP8`, and `iosDevelopmentTeamId`. Google Play service account JSON and App Store Connect API key id, issuer id, and P8 are edited in BuildCommit and stored temporarily on `BuildSettingsSO`. These are committed in `.build/build_request.json`; use them only for temporary experiments.
- Default credential fallback remains GitHub Actions Secrets/env: `ANDROID_KEYSTORE_PASS`, `ANDROID_KEYALIAS_PASS`, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, profile-prefixed App Store Connect secrets, and `ACTIONFIT_IOS_DEVELOPMENT_TEAM_ID`/`STORMBORN_IOS_DEVELOPMENT_TEAM_ID`.
- CI entry method: `ActionFit.BuildAutomation.Editor.CIBuildEntry.BuildFromRequest`.
- GitHub Actions template: `WorkflowTemplates/buildcommit-auto-build.yml`.
- Build Automation depends on `com.actionfit.buildsetting@1.1.1` or newer.
- The storage commit alone should not trigger CI. The pushed `build/**` tag is the actual CI request.
- `Platform=Both` is split by the workflow into Android and iOS jobs before calling `CIBuildEntry`.

## Release Note Rules

- `ActionFitPackageInfo_SO.ReleaseNote` must contain only the single version being prepared.
- Do not copy older changelog entries into the newest release note.
- Version history and update-range summaries are composed by Custom Package Manager from separate catalog version rows.
- Do not add headings such as `## 1.0.0` inside ReleaseNote unless a specific package UI requires it; the catalog row already carries the version.

## Publish Notes

- Publishing is manual through Custom Package Manager.
- The `Build_Automation` GitHub repository must exist before first publish.
- Before reusing a version, check the remote Git tags. Published tags are immutable.
- Publish or catalog-register the required `com.actionfit.buildsetting` version before publishing a Build Automation version that depends on it.
- The package repository should include this `AI_GUIDE.md` so other projects can load the AI package context after installing the package.

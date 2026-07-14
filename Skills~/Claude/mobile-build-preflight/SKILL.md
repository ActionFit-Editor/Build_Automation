---
name: mobile-build-preflight
description: Audit Build Automation package dependencies, project paths, workflow synchronization, safe request fields, and GitHub readiness without creating or running a build.
---

# Mobile Build Preflight

Keep this preflight read-only. Do not open AutoBuild, create or rewrite `.build/build_request.json`, change PlayerSettings or settings assets, synchronize `.github`, commit, tag, push, start Unity builds, upload artifacts, or deploy.

1. Read repository instructions plus the Build Automation and AI GitHub `README.md` and `AI_GUIDE.md` files.
2. Confirm the Git repository root, selected Unity project root, and `ProjectSettings/ProjectVersion.txt`. Report only paths inside the selected repository and the Unity version.
3. Inspect `Packages/manifest.json` and `Packages/packages-lock.json` for Build Automation and its declared Build Setting, Custom Symbols, and AI GitHub dependencies. Report package IDs, resolved versions, depth, and missing/outdated requirements.
4. Compare package-owned workflow/template files with repository-root `.github/workflows/buildcommit-auto-build.yml`, `.github/actions/build-android/action.yml`, `.github/actions/build-ios/action.yml`, and `.github/scripts/*` using read-only comparisons. Report `current`, `missing`, or `different`; never run workflow synchronization.
5. Check whether the repository workflow runs `allocate` on group `mobile-build-allocator` with label `runner-allocator`, calls `/Users/lydia/workspace/runner-allocator/bin/allocate-project-runner` without checkout, exposes `project_label` as `affinity_label`, and makes `mobile-build` depend on that output. Confirm that the mobile job refreshes `.unity-mobile-affinity.json`. `vars.UNITY_RUNNER_AFFINITY_LABEL` is an optional `project-*` override because the allocator otherwise derives it from the repository name. Do not query credential values or create, remove, or change runner labels, secrets, repository variables, or host files.
6. Check only whether expected Build Setting, Build Automation, and Custom Symbols settings assets exist. Do not print serialized contents because they may contain signing configuration.
7. If `.build/build_request.json` already exists, parse and report only this allowlist: `schemaVersion`, `triggerSource`, `unityProjectPath`, `platform`, `buildKind`, `uploadTarget`, `distributionProfile`, and `autoConfigureBuildSymbols`. Never print the raw file or any key containing `password`, `secret`, `token`, `key`, `certificate`, `profile`, `webhook`, `keystore`, or Base64 data; `distributionProfile` is the sole allowed profile-name field.
8. Use `$github-auth-diagnose` when it is installed and the user requests GitHub readiness. Otherwise report GitHub push readiness as `unknown`; do not start login or setup.
9. Report every prerequisite as `ready`, `not-ready`, or `unknown`, then list the exact non-mutating evidence and any write action that would require separate user approval.

Do not inspect runner secret roots, keychains, provisioning profiles, keystore files, or credential values. Runner-specific secret validation is a separate explicitly scoped operational task.

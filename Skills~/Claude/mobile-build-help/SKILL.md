---
name: mobile-build-help
description: Explain Build Automation, its installed skills, BuildCommit and runner architecture, menus, prerequisites, and read-only versus build-request boundaries.
---

# Build Automation Help

Answer in the user's language. Explain Build Automation without creating requests, changing settings, synchronizing workflows, committing, tagging, pushing, building, uploading, or deploying.

1. Read `PACKAGE_SKILLS.md` first. Treat its generated package identity, complete related-skill table, `$skill-name` invocations, descriptions, and access boundaries as authoritative.
2. Read `Packages/com.actionfit.buildautomation/README.md` and `Packages/com.actionfit.buildautomation/AI_GUIDE.md` when present. If downloaded, resolve `Library/PackageCache/com.actionfit.buildautomation@*` without editing it.
3. Explain these distinct boundaries:
   - `$mobile-build-preflight` performs a read-only local prerequisite and configuration-shape audit;
   - `AutoBuild` and `Commit, Tag & Push` create or synchronize files, commit, push, and trigger builds, so they require a separate explicit write workflow;
   - runner provisioning, signing, store upload, Slack notification, and deployment are external operational workflows.
4. Explain `BuildRequest` schema, repository-relative `unityProjectPath`, Build Setting/Custom Symbols/AI GitHub dependencies, workflow template synchronization, tag-triggered CI, and separate Android/iOS Unity processes.
5. State that help and preflight never read or print signing values, keystore data, tokens, webhook URLs, certificate/keychain contents, or the full `.build/build_request.json`.

List `AutoBuild`, `Setting SO`, and `README` under `Tools > Package > Build Automation`. Recommend the installed README and AI guide for current schema and runner requirements.

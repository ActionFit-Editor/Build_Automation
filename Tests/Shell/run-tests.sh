#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"

bash "$package_root/Tests/Shell/test-unity-project-paths.sh"
bash "$package_root/Tests/Shell/test-runner-secrets.sh"
bash "$package_root/Tests/Shell/test-affinity-workflow.sh"
bash "$package_root/Tests/Shell/test-store-upload-worker.sh"
node "$package_root/Tests/Shell/test-runner-allocator.js"

cmp \
  "$package_root/.github/scripts/validate-local-runner-secrets.sh" \
  "$package_root/RunnerSetup/validate-local-runner-secrets.sh"

repository_root="$(cd "$package_root/../.." && pwd -P)"
if [ -e "$repository_root/.git" ]; then
  assert_synced() {
    local package_path="$1"
    local repository_path="$2"
    if ! cmp "$package_path" "$repository_path"; then
      echo "Repository workflow asset is not synchronized: $repository_path" >&2
      exit 1
    fi
  }

  assert_synced "$package_root/WorkflowTemplates/buildcommit-auto-build.yml" "$repository_root/.github/workflows/buildcommit-auto-build.yml"
  assert_synced "$package_root/.github/actions/build-android/action.yml" "$repository_root/.github/actions/build-android/action.yml"
  assert_synced "$package_root/.github/actions/build-ios/action.yml" "$repository_root/.github/actions/build-ios/action.yml"
  assert_synced "$package_root/.github/scripts/store-upload-worker.rb" "$repository_root/.github/scripts/store-upload-worker.rb"
  assert_synced "$package_root/.github/scripts/upload-google-play.sh" "$repository_root/.github/scripts/upload-google-play.sh"
  assert_synced "$package_root/.github/scripts/upload-testflight.rb" "$repository_root/.github/scripts/upload-testflight.rb"
fi

echo "Build Automation shell tests passed"

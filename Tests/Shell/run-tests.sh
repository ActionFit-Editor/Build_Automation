#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"

bash "$package_root/Tests/Shell/test-unity-project-paths.sh"
bash "$package_root/Tests/Shell/test-runner-secrets.sh"
bash "$package_root/Tests/Shell/test-affinity-workflow.sh"
bash "$package_root/Tests/Shell/test-store-upload-worker.sh"
bash "$package_root/Tests/Shell/test-development-distribution.sh"
bash "$package_root/Tests/Shell/test-slack-apk-delivery-receipt.sh"
node "$package_root/Tests/Shell/test-runner-allocator.js"

cmp \
  "$package_root/.github/scripts/validate-local-runner-secrets.sh" \
  "$package_root/RunnerSetup/validate-local-runner-secrets.sh"

for build_runner_source in \
  "$package_root/.github/actions/build-android/action.yml" \
  "$package_root/.github/actions/build-ios/action.yml" \
  "$package_root/.github/scripts/ensure-unity-editor-modules.sh" \
  "$package_root/.github/scripts/validate-local-runner-secrets.sh" \
  "$package_root/RunnerSetup/validate-local-runner-secrets.sh"; do
  if grep -Eiq 'slack|webhook' "$build_runner_source"; then
    echo "Unity build runner source must not access Slack: $build_runner_source" >&2
    exit 1
  fi
done

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
  assert_synced "$package_root/.github/scripts/resolve-local-secret-root.sh" "$repository_root/.github/scripts/resolve-local-secret-root.sh"
  assert_synced "$package_root/.github/scripts/notify-slack-build-result.sh" "$repository_root/.github/scripts/notify-slack-build-result.sh"
  assert_synced "$package_root/.github/scripts/upload-slack-file.sh" "$repository_root/.github/scripts/upload-slack-file.sh"
  assert_synced "$package_root/.github/scripts/manage-slack-apk-delivery-receipt.rb" "$repository_root/.github/scripts/manage-slack-apk-delivery-receipt.rb"
  assert_synced "$package_root/.github/scripts/store-upload-worker.rb" "$repository_root/.github/scripts/store-upload-worker.rb"
  assert_synced "$package_root/.github/scripts/upload-google-play.sh" "$repository_root/.github/scripts/upload-google-play.sh"
  assert_synced "$package_root/.github/scripts/upload-testflight.rb" "$repository_root/.github/scripts/upload-testflight.rb"
  assert_synced "$package_root/.github/scripts/check-testflight-build-number.rb" "$repository_root/.github/scripts/check-testflight-build-number.rb"
fi

echo "Build Automation shell tests passed"

#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/../.." && pwd -P)"

bash "$package_root/Tests/Shell/test-unity-project-paths.sh"
bash "$package_root/Tests/Shell/test-runner-secrets.sh"
bash "$package_root/Tests/Shell/test-affinity-workflow.sh"
node "$package_root/Tests/Shell/test-runner-allocator.js"

cmp \
  "$package_root/.github/scripts/validate-local-runner-secrets.sh" \
  "$package_root/RunnerSetup/validate-local-runner-secrets.sh"

echo "Build Automation shell tests passed"

#!/usr/bin/env bash
set -euo pipefail

configured_root="${CI_SECRET_ROOT:-}"
resolved_root=""

resolve_candidate() {
  local candidate="$1"
  if [ ! -d "$candidate" ]; then
    return 1
  fi

  (
    cd "$candidate"
    pwd -P
  )
}

if [ -n "$configured_root" ]; then
  resolved_root="$(resolve_candidate "$configured_root")" || {
    echo "::error::Configured CI_SECRET_ROOT is not an accessible directory: $configured_root"
    exit 1
  }
else
  for candidate in \
    "$HOME/workspace/build-automation" \
    "/Volumes/ActionFitBuildAutomation" \
    "$HOME/ci-secrets/build-automation"; do
    if resolved_root="$(resolve_candidate "$candidate")"; then
      break
    fi
  done
fi

if [ -z "$resolved_root" ]; then
  echo "::error::Build automation secret bundle was not found."
  echo "::error::Mount the Mac Studio share at /Volumes/ActionFitBuildAutomation or set CI_SECRET_ROOT in the runner environment."
  exit 1
fi

if [ ! -d "$resolved_root/shared" ]; then
  echo "::error::Build automation shared secret directory is missing: $resolved_root/shared"
  exit 1
fi
if [[ "$resolved_root" == *$'\n'* || "$resolved_root" == *$'\r'* ]]; then
  echo "::error::CI_SECRET_ROOT contains control characters."
  exit 1
fi

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    printf 'CI_SECRET_ROOT<<__ACTIONFIT_SECRET_ROOT__\n'
    printf '%s\n' "$resolved_root"
    printf '__ACTIONFIT_SECRET_ROOT__\n'
  } >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'path=%s\n' "$resolved_root" >> "$GITHUB_OUTPUT"
fi

echo "Using runner-local build automation bundle: $resolved_root"

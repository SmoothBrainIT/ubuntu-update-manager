#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${REPOSITORY_ROOT}/ubuntu-update-manager.sh"

bash -n "$SCRIPT_PATH"

version_output="$(bash "$SCRIPT_PATH" version)"
if [[ "$version_output" != "ubuntu-update-manager 1.1.1" ]]; then
    printf 'Unexpected version output: %s\n' "$version_output" >&2
    exit 1
fi

help_output="$(bash "$SCRIPT_PATH" help)"
if [[ "$help_output" != *"uum <command> [options]"* ]]; then
    printf 'Help output is missing the uum command.\n' >&2
    exit 1
fi

for command in check-update doctor export-config preview self-update set-lock-timeout set-self-update; do
    if [[ "$help_output" != *"$command"* ]]; then
        printf 'Help output is missing command: %s\n' "$command" >&2
        exit 1
    fi
done

if [[ "$help_output" == *$'\r'* ]]; then
    printf 'Help output contains CRLF line endings.\n' >&2
    exit 1
fi

# shellcheck disable=SC1090,SC1091
source "$SCRIPT_PATH"

if ! version_is_newer 1.2.0 1.1.9 ||
    version_is_newer 1.1.1 1.1.1 ||
    version_is_newer 1.1.0 1.1.1; then
    printf 'Semantic version comparison failed.\n' >&2
    exit 1
fi

SELF_UPDATE_MODE="manual"
if ! self_update_enabled_for_run no || self_update_enabled_for_run yes; then
    printf 'Manual self-update mode selection failed.\n' >&2
    exit 1
fi
SELF_UPDATE_MODE="scheduled"
if self_update_enabled_for_run no || ! self_update_enabled_for_run yes; then
    printf 'Scheduled self-update mode selection failed.\n' >&2
    exit 1
fi
SELF_UPDATE_MODE="both"
if ! self_update_enabled_for_run no || ! self_update_enabled_for_run yes; then
    printf 'Combined self-update mode selection failed.\n' >&2
    exit 1
fi
SELF_UPDATE_MODE="off"
if [[ "$SELF_UPDATE_MODE" != "off" ]] ||
    self_update_enabled_for_run no || self_update_enabled_for_run yes; then
    printf 'Disabled self-update mode selection failed.\n' >&2
    exit 1
fi

update_fixture="$(mktemp)"
trap 'rm -f -- "$update_fixture"' EXIT
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'PROGRAM_NAME="ubuntu-update-manager"' \
    'PROGRAM_VERSION="1.2.0"' \
    'printf "fixture\\n"' >"$update_fixture"

if [[ "$(script_version "$update_fixture")" != "1.2.0" ]] ||
    ! validate_update_candidate "$update_fixture" 1.2.0; then
    printf 'Valid update fixture was rejected.\n' >&2
    exit 1
fi

printf '%s\n' 'PROGRAM_NAME="ubuntu-update-manager"' >>"$update_fixture"
if validate_update_candidate "$update_fixture" 1.2.0; then
    printf 'Ambiguous update fixture was accepted.\n' >&2
    exit 1
fi

printf 'Smoke tests passed.\n'

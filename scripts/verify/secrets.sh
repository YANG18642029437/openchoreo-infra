#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

patterns='BEGIN [A-Z ]*PRIVATE KEY|client-key-data:[[:space:]]*[A-Za-z0-9+/]{16,}={0,2}([[:space:]]|$)|client-certificate-data:[[:space:]]*[A-Za-z0-9+/]{16,}={0,2}([[:space:]]|$)|api[_-]?token[[:space:]]*[:=][[:space:]]*[^[:space:]$<{]'

scan_git_surface() {
  surface="$1"
  shift

  set +e
  git grep "$@" -l -E "$patterns" -- .
  scan_status=$?
  set -e

  case "$scan_status" in
    0)
      printf 'possible secret detected in %s; offending filenames listed above\n' "$surface" >&2
      return 1
      ;;
    1)
      return 0
      ;;
    *)
      printf 'secret scan failed for %s (git grep exit %s)\n' "$surface" "$scan_status" >&2
      return "$scan_status"
      ;;
  esac
}

untracked_list=''
cleanup() {
  if [ -n "$untracked_list" ]; then
    rm -f "$untracked_list"
  fi
}
trap cleanup EXIT HUP INT TERM

scan_untracked_files() {
  set +e
  untracked_list="$(mktemp "${TMPDIR:-/tmp}/openchoreo-secret-scan.XXXXXX")"
  scan_status=$?
  set -e
  if [ "$scan_status" -ne 0 ]; then
    printf 'secret scan failed to create temporary file (mktemp exit %s)\n' "$scan_status" >&2
    return "$scan_status"
  fi

  set +e
  git ls-files --others --exclude-standard -z >"$untracked_list"
  scan_status=$?
  set -e
  if [ "$scan_status" -ne 0 ]; then
    printf 'secret scan failed to list non-ignored untracked files (git exit %s)\n' "$scan_status" >&2
    return "$scan_status"
  fi

  untracked_files=()
  while IFS= read -r -d '' untracked_file; do
    untracked_files[${#untracked_files[@]}]="$untracked_file"
  done <"$untracked_list"

  if [ "${#untracked_files[@]}" -eq 0 ]; then
    return 0
  fi

  set +e
  grep -E -l -- "$patterns" "${untracked_files[@]}"
  scan_status=$?
  set -e

  case "$scan_status" in
    0)
      printf 'possible secret detected in non-ignored untracked files; offending filenames listed above\n' >&2
      return 1
      ;;
    1)
      return 0
      ;;
    *)
      printf 'secret scan failed for non-ignored untracked files (grep exit %s)\n' "$scan_status" >&2
      return "$scan_status"
      ;;
  esac
}

scan_git_surface 'tracked working tree'
scan_git_surface 'Git index' --cached
scan_untracked_files

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --redact --no-banner
else
  printf 'gitleaks unavailable; regex scan only\n'
fi

printf 'secret boundary: PASS\n'

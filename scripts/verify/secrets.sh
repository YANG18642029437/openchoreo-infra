#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

patterns='BEGIN [A-Z ]*PRIVATE KEY|client-key-data:[[:space:]]*[A-Za-z0-9+/]{16,}={0,2}([[:space:]]|$)|client-certificate-data:[[:space:]]*[A-Za-z0-9+/]{16,}={0,2}([[:space:]]|$)|api[_-]?token[[:space:]]*[:=][[:space:]]*[^[:space:]$<{]'

temporary_files=()

cleanup() {
  for temporary_file in "${temporary_files[@]}"; do
    rm -f -- "$temporary_file"
  done
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

create_temporary_file() {
  set +e
  new_temporary_file="$(mktemp "${TMPDIR:-/tmp}/openchoreo-secret-scan.XXXXXX")"
  scan_status=$?
  set -e
  if [ "$scan_status" -ne 0 ]; then
    printf 'secret scan failed to create temporary file (mktemp exit %s)\n' "$scan_status" >&2
    return "$scan_status"
  fi
  temporary_files[${#temporary_files[@]}]="$new_temporary_file"
}

print_escaped_filename() {
  printf '  %q\n' "$1" >&2
}

scan_git_surface() {
  surface="$1"
  shift

  create_temporary_file
  scan_results="$new_temporary_file"

  set +e
  git grep "$@" --null -l -E "$patterns" -- . >"$scan_results" 2>/dev/null
  scan_status=$?
  set -e

  case "$scan_status" in
    0)
      printf 'possible secret detected in %s:\n' "$surface" >&2
      while IFS= read -r -d '' offending_file; do
        print_escaped_filename "$offending_file"
      done <"$scan_results"
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

scan_untracked_files() {
  create_temporary_file
  untracked_list="$new_temporary_file"

  set +e
  git ls-files --others --exclude-standard -z >"$untracked_list" 2>/dev/null
  scan_status=$?
  set -e
  if [ "$scan_status" -ne 0 ]; then
    printf 'secret scan failed to list non-ignored untracked files (git exit %s)\n' "$scan_status" >&2
    return "$scan_status"
  fi

  found_secret=0
  while IFS= read -r -d '' untracked_file; do
    set +e
    grep -E -q -- "$patterns" "$untracked_file" 2>/dev/null
    scan_status=$?
    set -e

    case "$scan_status" in
      0)
        print_escaped_filename "$untracked_file"
        found_secret=1
        ;;
      1)
        ;;
      *)
        printf 'secret scan failed for non-ignored untracked file ' >&2
        printf '%q' "$untracked_file" >&2
        printf ' (grep exit %s)\n' "$scan_status" >&2
        return "$scan_status"
        ;;
    esac
  done <"$untracked_list"

  if [ "$found_secret" -eq 1 ]; then
    printf 'possible secret detected in non-ignored untracked files; offending filenames listed above\n' >&2
    return 1
  fi
}

is_ignored_path_exempt() {
  case "$1" in
    .private|.private/*|.worktrees|.worktrees/*|.git|.git/*|\
    .terraform|.terraform/*|*/.terraform/*|\
    .cache|.cache/*|*/.cache/*|node_modules|node_modules/*|*/node_modules/*|\
    .pytest_cache|.pytest_cache/*|*/.pytest_cache/*|\
    .mypy_cache|.mypy_cache/*|*/.mypy_cache/*|\
    .ruff_cache|.ruff_cache/*|*/.ruff_cache/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_sensitive_ignored_path() {
  case "$1" in
    *.pem|*.key|*.p12|*.kubeconfig|kubeconfig*|*/kubeconfig*|\
    *.tfstate|*.tfstate.*|*.tfvars|\
    .env|.env.*|*/.env|*/.env.*|\
    ansible/vault-password*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_ignored_filename_policy() {
  create_temporary_file
  ignored_list="$new_temporary_file"

  set +e
  git ls-files --others --ignored --exclude-standard -z >"$ignored_list" 2>/dev/null
  scan_status=$?
  set -e
  if [ "$scan_status" -ne 0 ]; then
    printf 'secret scan failed to list ignored files (git exit %s)\n' "$scan_status" >&2
    return "$scan_status"
  fi

  found_sensitive_name=0
  while IFS= read -r -d '' ignored_file; do
    if is_ignored_path_exempt "$ignored_file"; then
      continue
    fi
    if is_sensitive_ignored_path "$ignored_file"; then
      print_escaped_filename "$ignored_file"
      found_sensitive_name=1
    fi
  done <"$ignored_list"

  if [ "$found_sensitive_name" -eq 1 ]; then
    printf 'sensitive-looking ignored files must be stored under .private; offending filenames listed above\n' >&2
    return 1
  fi
}

scan_git_surface 'tracked working tree'
scan_git_surface 'Git index' --cached
scan_untracked_files
check_ignored_filename_policy

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --redact --no-banner
else
  if [ "${REQUIRE_GITLEAKS:-0}" = 1 ]; then
    printf 'gitleaks is required but unavailable\n' >&2
    exit 1
  fi
  printf 'gitleaks unavailable; regex scan only\n'
fi

printf 'secret boundary: PASS\n'

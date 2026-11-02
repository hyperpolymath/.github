#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Narrow, fail-closed contracts for this repository's workflow coordinates.
# This is not a replacement for `gh actions-lock --verify`; it catches the
# estate-specific regressions that a syntactically valid lock can still hide:
# moved reusable owners, non-immutable reusable pins, missing SPDX headers,
# and an inline notification-action SHA that disagrees with actions.lock.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
WF_DIR="$ROOT/.github/workflows"
LOCK="$WF_DIR/actions.lock"
failures=0

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  failures=$((failures + 1))
}

[ -d "$WF_DIR" ] || { echo "no workflow directory: $WF_DIR" >&2; exit 2; }
[ -f "$LOCK" ] || { echo "no actions.lock: $LOCK" >&2; exit 2; }

shopt -s nullglob
workflows=("$WF_DIR"/*.yml "$WF_DIR"/*.yaml)
[ "${#workflows[@]}" -gt 0 ] || { echo "no workflow files" >&2; exit 2; }

for wf in "${workflows[@]}"; do
  rel=".github/workflows/$(basename "$wf")"

  if [ "$(head -n 1 "$wf")" != '# SPDX-License-Identifier: MPL-2.0' ]; then
    fail "$rel: SPDX-License-Identifier must be the first line"
  fi

  if ! grep -Fq "    '$rel':" "$LOCK"; then
    fail "$rel: missing actions.lock workflows entry"
  fi

  if grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*hyperpolymath/standards/' "$wf"; then
    fail "$rel: pre-transfer hyperpolymath/standards reusable coordinate"
  fi

  while IFS= read -r line; do
    ref=$(printf '%s\n' "$line" | sed -E 's/^[^@]*@([^ #]+).*/\1/')
    if [[ ! "$ref" =~ ^[0-9a-f]{40}$ ]]; then
      fail "$rel: remote reusable must be pinned to a 40-hex commit: $line"
    fi
  done < <(grep -E '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[^@[:space:]]+@' "$wf" || true)
done

# The notification action is tag-pinned in YAML because actions.lock is the
# pin authority. Its inline comment must name the same commit as the lock.
notify="$WF_DIR/push-email-notify.yml"
if [ -f "$notify" ]; then
  uses_line=$(grep -E '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*hyperpolymath/smtp-notify-action@' "$notify" | head -n 1 || true)
  if [ -z "$uses_line" ]; then
    fail "push-email-notify.yml: missing smtp-notify-action uses line"
  else
    tag=$(printf '%s\n' "$uses_line" | sed -E 's/^[^@]*@([^ #]+).*/\1/')
    sha=$(printf '%s\n' "$uses_line" | sed -nE 's/.*sha1-([0-9a-f]{40}).*/\1/p')
    case "$tag" in
      v[0-9]*.[0-9]*.[0-9]*) ;;
      *) fail "push-email-notify.yml: expected an exact release tag, got $tag" ;;
    esac
    if [ -z "$sha" ]; then
      fail "push-email-notify.yml: missing inline sha1 pin comment"
    fi
    key="    'hyperpolymath/smtp-notify-action@$tag':"
    if ! grep -Fq "$key" "$LOCK"; then
      fail "actions.lock: missing dependency key for smtp-notify-action@$tag"
    fi
    if ! grep -A4 -F "$key" "$LOCK" | grep -Fq "commit: 'sha1-$sha'"; then
      fail "actions.lock: smtp-notify-action@$tag commit does not match inline sha1-$sha"
    fi
    if ! grep -Fq "        - 'hyperpolymath/smtp-notify-action@$tag'" "$LOCK"; then
      fail "actions.lock: push-email-notify.yml does not reference smtp-notify-action@$tag"
    fi
  fi
fi

if [ "$failures" -gt 0 ]; then
  printf '%s workflow contract failure(s)\n' "$failures" >&2
  exit 1
fi
echo 'workflow contracts: OK'

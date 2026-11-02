#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/check-workflow-contracts.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0
fail=0

fixture() {
  root="$WORK/$1"
  mkdir -p "$root/.github/workflows"
  cat > "$root/.github/workflows/actions.lock" <<'LOCK'
version: 'v0.0.3'
workflows:
    '.github/workflows/push-email-notify.yml':
        - 'hyperpolymath/smtp-notify-action@v0.5.1'
    '.github/workflows/secret-scanner.yml': []
dependencies:
    'hyperpolymath/smtp-notify-action@v0.5.1':
        ref: 'v0.5.1'
        commit: 'sha1-e384daf6167a7a7567642d6a62060106244d2413'
LOCK
  cat > "$root/.github/workflows/push-email-notify.yml" <<'YAML'
# SPDX-License-Identifier: MPL-2.0
name: Push email notification
jobs:
  notify:
    steps:
      - uses: hyperpolymath/smtp-notify-action@v0.5.1 # NOSONAR — pin authority is actions.lock (sha1-e384daf6167a7a7567642d6a62060106244d2413)
YAML
  cat > "$root/.github/workflows/secret-scanner.yml" <<'YAML'
# SPDX-License-Identifier: MPL-2.0
name: Secret Scanner
jobs:
  scan:
    uses: metadatastician/standards/.github/workflows/secret-scanner-reusable.yml@8d1a2aab4211493cf42f147f2080f024605797dc
YAML
}

expect() {
  name="$1"; want="$2"; root="$3"
  set +e
  bash "$SCRIPT" "$root" >"$WORK/out" 2>&1
  got=$?
  set -e
  if [ "$got" -eq "$want" ]; then
    printf 'PASS %s\n' "$name"; pass=$((pass + 1))
  else
    printf 'FAIL %s: wanted exit %s, got %s\n' "$name" "$want" "$got" >&2
    cat "$WORK/out" >&2
    fail=$((fail + 1))
  fi
}

fixture valid
expect valid 0 "$WORK/valid"

fixture stale_sha
sed -i 's/sha1-e384daf6167a7a7567642d6a62060106244d2413/sha1-ede1191ef6ff3ac02c4f4d9efdf837ee517e11d7/' "$WORK/stale_sha/.github/workflows/push-email-notify.yml"
expect stale_inline_sha 1 "$WORK/stale_sha"

fixture moved_owner
sed -i 's#metadatastician/standards/#hyperpolymath/standards/#' "$WORK/moved_owner/.github/workflows/secret-scanner.yml"
expect moved_reusable_owner 1 "$WORK/moved_owner"

fixture floating_pin
sed -i 's/@8d1a2aab4211493cf42f147f2080f024605797dc/@main/' "$WORK/floating_pin/.github/workflows/secret-scanner.yml"
expect floating_reusable_pin 1 "$WORK/floating_pin"

fixture quoted_moved_owner
sed -i 's#uses: metadatastician/standards/.github/workflows/secret-scanner-reusable.yml@8d1a2aab4211493cf42f147f2080f024605797dc#uses: "hyperpolymath/standards/.github/workflows/secret-scanner-reusable.yml@8d1a2aab4211493cf42f147f2080f024605797dc"#' "$WORK/quoted_moved_owner/.github/workflows/secret-scanner.yml"
expect quoted_moved_reusable_owner 1 "$WORK/quoted_moved_owner"

fixture quoted_floating_pin
sed -i "s#uses: metadatastician/standards/.github/workflows/secret-scanner-reusable.yml@8d1a2aab4211493cf42f147f2080f024605797dc#uses: 'metadatastician/standards/.github/workflows/secret-scanner-reusable.yml@main'#" "$WORK/quoted_floating_pin/.github/workflows/secret-scanner.yml"
expect quoted_floating_reusable_pin 1 "$WORK/quoted_floating_pin"

fixture missing_spdx
sed -i '1s/.*/# managed/' "$WORK/missing_spdx/.github/workflows/secret-scanner.yml"
expect missing_spdx_first_line 1 "$WORK/missing_spdx"

fixture missing_lock_entry
sed -i "/secret-scanner.yml':/d" "$WORK/missing_lock_entry/.github/workflows/actions.lock"
expect missing_lock_workflow_entry 1 "$WORK/missing_lock_entry"

fixture synthetic_reusable_edge
sed -i "s#'.github/workflows/secret-scanner.yml': \[\]#'.github/workflows/secret-scanner.yml':\n        - 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'#" "$WORK/synthetic_reusable_edge/.github/workflows/actions.lock"
expect synthetic_reusable_only_lock_edge 1 "$WORK/synthetic_reusable_edge"

fixture second_smtp_stale
cat >> "$WORK/second_smtp_stale/.github/workflows/push-email-notify.yml" <<'YAML'
  second:
    steps:
      - uses: hyperpolymath/smtp-notify-action@v0.5.1 # sha1-ede1191ef6ff3ac02c4f4d9efdf837ee517e11d7
YAML
expect second_smtp_use_stale_sha 1 "$WORK/second_smtp_stale"

fixture second_smtp_missing_sha
cat >> "$WORK/second_smtp_missing_sha/.github/workflows/push-email-notify.yml" <<'YAML'
  second:
    steps:
      - uses: hyperpolymath/smtp-notify-action@v0.5.1
YAML
expect second_smtp_use_missing_inline_sha 1 "$WORK/second_smtp_missing_sha"

fixture duplicate_yaml_key
printf '\njobs: {}\n' >> "$WORK/duplicate_yaml_key/.github/workflows/secret-scanner.yml"
expect duplicate_yaml_key_not_inspected 2 "$WORK/duplicate_yaml_key"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

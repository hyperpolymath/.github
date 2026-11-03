#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Narrow, fail-closed workflow contracts for hyperpolymath/.github.

This is not a replacement for `gh actions-lock --verify`. It catches the
estate-specific regressions that a syntactically valid lock can still hide:
moved reusable owners, non-immutable reusable pins, missing SPDX headers,
synthetic lock edges for remote reusable workflows, and inline notification
action SHAs that disagree with actions.lock.

Exit codes:
  0  every inspected contract passed
  1  at least one contract violation
  2  not inspected (missing input, unreadable YAML, missing PyYAML)
"""

from __future__ import annotations

import pathlib
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment failure, not a pass
    print("ERROR: PyYAML is required to inspect workflow contracts", file=sys.stderr)
    sys.exit(2)


class UniqueKeyLoader(yaml.SafeLoader):
    """SafeLoader that rejects duplicate mapping keys instead of hiding them."""


def _unique_mapping(loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False) -> dict:
    loader.flatten_mapping(node)
    result: dict = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"duplicate YAML key: {key!r}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _unique_mapping)

REMOTE_REUSABLE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[^@]+@(.+)$")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SMTP_REF = re.compile(r"^hyperpolymath/smtp-notify-action@(v[0-9]+\.[0-9]+\.[0-9]+)$")
LOCAL_SCANNER = "./.github/workflows/secret-scanner-reusable.yml"
VENDORED_SCANNER_PIN = "8d1a2aab4211493cf42f147f2080f024605797dc"
INLINE_SHA = re.compile(r"sha1-([0-9a-f]{40})")

failures: list[str] = []


def fail(message: str) -> None:
    """Report a contract violation and count it for the final exit status."""
    failures.append(message)


def load_yaml(path: pathlib.Path):
    try:
        text = path.read_text(encoding="utf-8")
        return yaml.load(text, Loader=UniqueKeyLoader), text
    except Exception as exc:
        print(f"ERROR: cannot inspect {path}: {exc}", file=sys.stderr)
        sys.exit(2)


def iter_uses(node, path=()):
    """Yield (value, zero-based line, path) for every scalar `uses:` key."""
    if isinstance(node, yaml.MappingNode):
        for key_node, value_node in node.value:
            if not isinstance(key_node, yaml.ScalarNode):
                continue
            key = key_node.value
            if key == "uses" and isinstance(value_node, yaml.ScalarNode):
                yield value_node.value, value_node.start_mark.line, path
            yield from iter_uses(value_node, path + (key,))
    elif isinstance(node, yaml.SequenceNode):
        for index, item in enumerate(node.value):
            yield from iter_uses(item, path + (str(index),))


def main() -> int:
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path.cwd()
    wf_dir = root / ".github" / "workflows"
    lock_path = wf_dir / "actions.lock"

    if not wf_dir.is_dir():
        print(f"ERROR: no workflow directory: {wf_dir}", file=sys.stderr)
        return 2
    if not lock_path.is_file():
        print(f"ERROR: no actions.lock: {lock_path}", file=sys.stderr)
        return 2

    workflows = sorted(list(wf_dir.glob("*.yml")) + list(wf_dir.glob("*.yaml")))
    if not workflows:
        print("ERROR: no workflow files", file=sys.stderr)
        return 2

    lock, _ = load_yaml(lock_path)
    if not isinstance(lock, dict):
        print("ERROR: actions.lock is not a mapping", file=sys.stderr)
        return 2
    lock_workflows = lock.get("workflows")
    dependencies = lock.get("dependencies")
    if not isinstance(lock_workflows, dict) or not isinstance(dependencies, dict):
        print("ERROR: actions.lock workflows/dependencies are not mappings", file=sys.stderr)
        return 2

    for wf in workflows:
        rel = f".github/workflows/{wf.name}"
        try:
            first_line = wf.read_text(encoding="utf-8").splitlines()[0]
        except Exception as exc:
            print(f"ERROR: cannot read {rel}: {exc}", file=sys.stderr)
            return 2
        if first_line != "# SPDX-License-Identifier: MPL-2.0":
            fail(f"{rel}: SPDX-License-Identifier must be the first line")

        if rel not in lock_workflows:
            fail(f"{rel}: missing actions.lock workflows entry")
            entry = []
        else:
            entry = lock_workflows[rel]
            if not isinstance(entry, list):
                fail(f"{rel}: actions.lock workflow entry is not a list")
                entry = []

        data, text = load_yaml(wf)
        try:
            composed = yaml.compose(text, Loader=yaml.SafeLoader)
        except Exception as exc:
            print(f"ERROR: cannot compose {rel}: {exc}", file=sys.stderr)
            return 2
        lines = text.splitlines()
        uses = list(iter_uses(composed)) if composed is not None else []

        has_step_use = False
        has_remote_reusable = False
        for value, line_no, path in uses:
            if not isinstance(value, str):
                fail(f"{rel}:{line_no + 1}: uses value is not a string")
                continue
            if "steps" in path:
                has_step_use = True

            if value.startswith("hyperpolymath/standards/"):
                fail(f"{rel}:{line_no + 1}: pre-transfer hyperpolymath/standards coordinate: {value}")

            if value.startswith("./.github/workflows/"):
                local_target = root / value[2:]
                if not local_target.is_file():
                    fail(f"{rel}:{line_no + 1}: local reusable workflow does not exist: {value}")

            if "/.github/workflows/" in value and not value.startswith(("./", "$/")):
                has_remote_reusable = True
                match = REMOTE_REUSABLE.match(value)
                if not match:
                    fail(f"{rel}:{line_no + 1}: remote reusable must name an exact ref: {value}")
                elif not SHA40.match(match.group(1)):
                    fail(f"{rel}:{line_no + 1}: remote reusable must be pinned to a 40-hex commit: {value}")

        # gh-actions-lock v0.4.0 does not follow remote job-level reusable
        # workflows. A synthetic through-ref under a reusable-only caller is
        # an unused pin and fails --verify. Keep the reviewed closure TSV as
        # the trust record, but do not put that edge in the caller lock entry.
        if has_remote_reusable and not has_step_use and entry:
            fail(f"{rel}: reusable-only workflow must have an empty actions.lock entry")

        for pin in entry:
            if not isinstance(pin, str):
                fail(f"{rel}: non-string actions.lock pin: {pin!r}")
            elif pin not in dependencies:
                fail(f"{rel}: actions.lock pin has no dependency record: {pin}")

        if wf.name == "secret-scanner.yml":
            scanner_uses = [v for v, _line, path in uses if isinstance(v, str) and "jobs" in path and "steps" not in path]
            if scanner_uses != [LOCAL_SCANNER]:
                fail(f"{rel}: must call the local vendored scanner {LOCAL_SCANNER} (Actions allowlist blocks the remote standards reusable)")
            vendored = wf_dir / "secret-scanner-reusable.yml"
            if not vendored.is_file():
                fail(f"{rel}: vendored scanner missing: {vendored}")
            else:
                vtext = vendored.read_text(encoding="utf-8")
                if f"at {VENDORED_SCANNER_PIN}." not in vtext:
                    fail(f"{rel}: vendored scanner missing provenance pin {VENDORED_SCANNER_PIN}")
                if "ref: ${{ job.workflow_sha }}" in vtext:
                    fail(f"{rel}: vendored scanner must pin standards baseline explicitly, not job.workflow_sha")

        if wf.name == "push-email-notify.yml":
            smtp_count = 0
            for value, line_no, _path in uses:
                if not isinstance(value, str):
                    continue
                if value.startswith("hyperpolymath/smtp-notify-action@"):
                    smtp_count += 1
                    match = SMTP_REF.match(value)
                    if not match:
                        fail(f"{rel}:{line_no + 1}: smtp-notify-action must use an exact semver tag: {value}")
                        continue
                else:
                    continue
                tag = match.group(1)
                raw_line = lines[line_no] if line_no < len(lines) else ""
                inline = INLINE_SHA.search(raw_line)
                if not inline:
                    fail(f"{rel}:{line_no + 1}: missing inline sha1 pin comment")
                    continue
                sha = inline.group(1)
                key = f"hyperpolymath/smtp-notify-action@{tag}"
                dep = dependencies.get(key)
                if not isinstance(dep, dict):
                    fail(f"actions.lock: missing dependency record for {key}")
                elif dep.get("commit") != f"sha1-{sha}":
                    fail(f"actions.lock: {key} commit does not match inline sha1-{sha}")
                if value not in entry:
                    fail(f"actions.lock: {rel} does not reference {value}")
            if smtp_count == 0:
                fail(f"{rel}: missing smtp-notify-action uses line")

    for key, dep in dependencies.items():
        if not isinstance(dep, dict):
            fail(f"actions.lock: dependency {key} is not a mapping")
            continue
        commit = dep.get("commit")
        if not isinstance(commit, str) or not re.match(r"^sha1-[0-9a-f]{40}$", commit):
            fail(f"actions.lock: dependency {key} has invalid commit: {commit!r}")
        ref = dep.get("ref")
        key_sha = key.rsplit("@", 1)[-1]
        if SHA40.match(key_sha) and isinstance(ref, str) and ref == key_sha and "uses" not in dep:
            fail(f"actions.lock: dependency {key} repeats its own SHA in ref")

    if failures:
        for message in failures:
            print(f"ERROR: {message}", file=sys.stderr)
        print(f"{len(failures)} workflow contract failure(s)", file=sys.stderr)
        return 1
    print("workflow contracts: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

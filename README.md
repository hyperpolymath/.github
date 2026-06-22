<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# `.github` — community-health defaults for `hyperpolymath/*`

This repository is the **single source of truth** for default issue templates,
discussion templates, and community-health files across the entire
`hyperpolymath` organization.

GitHub automatically applies the files here to **every** repository in the
organization that does **not** provide its own. Improve a template once, here,
and the improvement reaches all ~290 repositories at once.

> **This is the place to propose improvements.** Open a PR against this repo and
> every repository benefits.

## What's inherited org-wide

| File / folder                         | What it provides                                  |
| ------------------------------------- | ------------------------------------------------- |
| `.github/ISSUE_TEMPLATE/*.yml`        | Issue forms (the "New issue" chooser)             |
| `.github/ISSUE_TEMPLATE/config.yml`   | Chooser config + contact links                    |
| `.github/DISCUSSION_TEMPLATE/*.yml`   | Discussion category forms                         |
| `PULL_REQUEST_TEMPLATE.md`            | Default PR template                                |
| `CODE_OF_CONDUCT.md`                  | Code of Conduct                                    |
| `CONTRIBUTING.md`                     | Contribution guide                                 |
| `SECURITY.md`                         | Security / disclosure policy                        |
| `SUPPORT.md`                          | Where to get help                                  |
| `GOVERNANCE.md`                       | How decisions are made                             |
| `FUNDING.yml`                         | Sponsor links (commented out by default)           |
| `profile/README.md`                   | The organization profile page                      |

> ℹ️ **Licence files are *not* inheritable.** GitHub does not propagate a default
> `LICENSE`. Each repository must carry its own.

## The two override rules (important)

1. **Issue & discussion templates are all-or-nothing per repo.** If a repository
   has *any* file in its own `.github/ISSUE_TEMPLATE/`, GitHub ignores **all** of
   the defaults here for that repo. Same for `DISCUSSION_TEMPLATE/`. So to inherit
   the canonical set, a repo must have **no** local template folder.
2. **Single files override individually.** A repo with its own `SECURITY.md`
   (etc.) uses that file and inherits the rest.

Many repos currently ship their own `.github/ISSUE_TEMPLATE/` — those will keep
using their local copies until they're retired in favour of these defaults. That
clean-up is intentionally a separate, owner-gated pass.

## The issue templates

| Template                     | When to use it                                          |
| ---------------------------- | ------------------------------------------------------- |
| 🐛 Bug report                | Something is broken or behaves incorrectly              |
| ✨ Feature request           | Propose new functionality                               |
| 📖 Documentation             | Docs are wrong, missing, unclear, or stale              |
| ❓ Question                  | Specific question wanting a tracked answer              |
| 🕳️ Soundness hole            | Type/borrow/resource/proof false-negative (top priority)|
| 🛡️ Dependency / advisory     | Published CVE/GHSA/RUSTSEC or a dependency bump          |
| 🪞 Affirmation / claim drift | A public claim overstates what the code does            |
| 🔧 Build / CI / tooling      | Build break, CI failure, required-check deadlock, Guix   |
| ⚡ Performance               | Slowdown, regression, or excessive resource use          |
| 🧹 Refactor / tech debt      | Behaviour-preserving internal cleanup                    |
| 📋 Task / other              | Tracked work that fits nothing above                     |

The 🕳️, 🛡️, 🪞, and 🔧 templates encode this estate's working culture
(holes-first, ground-truth-over-status-docs, the AFFIRMATION discipline, and the
recurring required-check-deadlock pain).

## The discussion forms

`q-a` · `ideas` · `show-and-tell` · `general` · `announcements`.

> ⚠️ **Filenames must match the category *slug*** (e.g. `q-a.yml` for "Q&A"). A
> form only appears if a category with that slug exists in the repo **and**
> Discussions is enabled there. Polls do not support forms.

## A note on `config.yml` contact links

The chooser's `contact_links` are **static URLs** — they can't be rewritten per
target repository, so they point at org-central locations (this repo's
Discussions and `SECURITY.md`). Individual repos can override `config.yml` to
point at their own.

## Licensing

Code and configuration in this repo are `MPL-2.0`; prose documentation is
`CC-BY-SA-4.0`. See each file's `SPDX-License-Identifier` header.

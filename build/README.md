# XRA-Lite — build tooling

This folder is XRA-Lite's **own build tooling**. Like the top-level `README.md` and `LICENSE`, it is
**NOT part of the pristine upstream subset** — it is our addition, used to produce the slim repo.
None of the files here are upstream SystemAnimatorOnline code.

It is shipped in the repo so anyone can reproduce the trim themselves.

## Contents

| Path | What it is |
|---|---|
| `GUIDE.md` | the full human guide — what the sync does, gotchas, how to run it, verification |
| `AGENTS.md` | the fast runbook for driving the sync with an **AI agent** (how to run, when to stop) |
| `sync/import-upstream.sh` | the whole sync pipeline (one script): clone → filter → gates → snapshot → push |
| `sync/vendor/git-filter-repo` | pinned, vendored git-filter-repo (no install needed) |
| `filter/*.txt` | the keep/drop **policy**: allowlist, droplist, required-files gate, watch-roots, replacements |

## Quick start

```sh
# from a clone of this repo:
bash build/sync/import-upstream.sh                # build + gates + drift report, NO push
FORCE_PUSH=1 bash build/sync/import-upstream.sh    # also force-push the new snapshot
```

Read `GUIDE.md` first for the full picture (and the gotchas that each cost a debug cycle).
Driving it with an AI agent? Read `AGENTS.md`.

## Note on paths

In this repo the tooling lives under `build/`. On the maintainer's machine it lives at the
playground root next to a `github/` checkout (the script computes its own location, so both layouts
work). `GUIDE.md` describes the maintainer layout; translate `sync/` → `build/sync/` and
`filter/` → `build/filter/` when running from a clone.

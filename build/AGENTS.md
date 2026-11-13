# XRA-Lite — AI / agent runbook

A short operating guide for anyone driving the XRA-Lite re-sync **with an AI agent**. If you are a
human, read `GUIDE.md` instead (it has the full rationale + gotchas). This file is the fast path for
an agent: how to run the sync, how to tell it worked, and when to stop and ask a human.

> This `build/` folder is XRA-Lite's **own build tooling** — it is NOT part of the pristine
> upstream subset. Editing files in `build/` is fine. Editing the product tree is NOT (see rules).

## What the tool does

`sync/import-upstream.sh` mechanically rebuilds the slim repo from upstream
`github.com/ButzYung/SystemAnimatorOnline`: fresh clone → filter to an allowlist → drop proven
dead-weight → run gates → write ONE orphan-commit snapshot (`filtered tree + our overlay + this
build/`) → gc → optional force-push. It is deterministic and re-runnable; it keeps no upstream
history (the drift report is how "what's new" surfaces).

## How to run

```sh
bash build/sync/import-upstream.sh                 # BUILD ONLY — build + gates + drift report, no push
FORCE_PUSH=1 bash build/sync/import-upstream.sh     # also force-push the new snapshot to origin
bash build/sync/import-upstream.sh <UPSTREAM_SHA>   # pin a specific upstream commit (default: master HEAD)
```

- **Always run build-only first and inspect**, then push.
- `FORCE_PUSH=1` uses plain `--force` by design (history is rewritten every sync, so
  `--force-with-lease` always rejects). Only publish upstream versions you have confirmed run.
- State written on the playground side (NOT committed to the slim repo):
  `filter/last-upstream-sha` (new baseline) and `last-drift-report.txt` (this run's drift).

## What success looks like

- Script **exits 0** and prints a `=== IMPORT COMPLETE ===` block with: `upstream OLD -> NEW`,
  upstream original size, slim size, bytes saved (+%), `.git` size, and the drift-report line count.
- All gates passed (each aborts loudly on failure):
  - **required-files** — every path in `filter/required.txt` still exists post-filter. A miss means
    upstream renamed/moved a core file.
  - **upstream-ancestor** — the new SHA is a descendant of the last baseline. A failure means
    upstream rewrote history / force-pushed.
  - **min-size floor** — the slim tree is above a sanity floor (≥50 files, ≥5 MB). A trip means a
    catastrophic over-trim.
  - **neutralization asserts** — only if `filter/replacements.txt` has active rules (currently none).

## When to STOP and ask a human

- **Any gate aborts.** Do not "fix" by loosening the gate. Surface the exact error.
- **Drift report is NON-EMPTY** (`last-drift-report.txt` has lines). Upstream added/renamed a file
  near the app surface. Review each entry: a new core file may need adding to
  `filter/allowlist.txt` (and possibly `filter/required.txt` / `filter/watch-roots.txt`) before you
  publish. Do not blindly re-run.
- **Slim size swings a lot** vs. the previous run with no obvious reason.

## Optional extra verification an agent can add for its users

The sync only proves files are **present**, not that mocap **runs**. These are optional, not
required by the pristine model — add them if they help your users:

- Serve `github/` with COOP/COEP headers (and `.xml` as `application/xml`) and headless-load
  `XR_Animator.html`; confirm it boots past 88% (an 88% stall = a missing default-scene asset pack).
- Diff this run's `git -C github ls-files` against the previous run's to see exactly what entered/left.
- Re-assert `filter/required.txt` against the pushed tree as an independent check.
- See `GUIDE.md` ("After a sync: verify it still works") — the old automated `smoketest/`
  (puppeteer + fake camera + COOP/COEP server) was removed after launch; rebuild it if you want
  automated regression.

## Hard rules for agents editing this project

1. **The product tree must stay a pristine, byte-for-byte subset of upstream.** Never edit app
   code, assets, or config to "fix" something. Any integration/patch belongs in the successor
   project, never here.
2. **Policy changes only.** You may edit the keep/drop policy (`filter/*.txt`) and this `build/`
   tooling. Replacements in `filter/replacements.txt` may be **subtractive only** (disabling
   references to dropped legacy code) — never additive.
3. **No AI-authorship references** in any committed product file or commit message. The automation
   disclosure in the top-level `README.md` is the single allowed mention that automation runs this.
4. **Prove before you drop.** Before adding to `filter/droplist.txt`, prove the path is never
   fetched during a full tracking session (face + pose Normal AND Best + hands + expressions).

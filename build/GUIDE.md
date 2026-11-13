# XRA-Lite — operating manual & design notes

Self-contained reference. Assumes NO prior knowledge — read this if you (human or AI) are
coming to this folder cold.

## What XRA-Lite is

A **slim, pristine extract** of the XR Animator web app from upstream
`github.com/ButzYung/SystemAnimatorOnline` ("SAO", ~698 MB, 10+ years, heavily cluttered).
`github/` contains ONLY the files needed to run XR Animator's webcam→VRM motion capture
(face, hands, fingers, body, expressions), trimmed from ~698 MB to ~205 MB.

**Published to:** `github.com/Ron81/XRA-Lite` (**public**). The monthly sync force-pushes the
new snapshot there. The `github/` repo's `origin` remote already points at it, so the push
target travels with the folder — no need to re-add it after a move.

**Why it exists:** it is a lean, always-current, low-maintenance reference of just the mocap
web app — one building block for a larger successor project (which combines XRA-Lite's capture
with a WebRTC transport and a separate server/renderer). **XRA-Lite itself holds NO
integration code** — it is kept a pure mechanical subset of upstream so it can be re-synced
cheaply. Any project-specific code belongs in the successor, never here.

### Where this fits (strategic context)

XRA-Lite is **building block #1** of a future (as-yet-unnamed) successor to the "ChaosWorld"
project. The successor is planned to combine:
- **XRA-Lite** — webcam capture + client-side solve (produces bone rotations + expression weights),
- **Posy** — an avatar-pose-over-WebRTC protocol / SFU transport that carries that *solved* data
  (not raw video or landmarks) between participants,
- **ChaosWorld parts** — the server, rooms, and rendering of remote participants' avatars.

The successor's integration/patch layer (tapping XRA's solved output into Posy, etc.) lives in
**that** project — XRA-Lite and Posy are both kept pristine. XRA-Lite is also useful as a quality
reference/oracle (its mocap is excellent) when building the successor's own capture path.

**License:** upstream is CC BY-NC-SA 4.0 (attribution, non-commercial, share-alike). The fork
carries the same. All credit is Butz Yung / Anime Theme's. See `github/README.md` + `overlay/LICENSE`.

## Folder layout

```
XRA-Lite/
├── README.md            # quick start (the one command)
├── details.md           # THIS FILE
├── github/              # the product — the XRA-Lite git repo (push target)
├── sync/
│   ├── import-upstream.sh    # the whole sync pipeline (one script)
│   └── vendor/git-filter-repo # pinned v2.47.0, vendored (no install needed)
├── filter/              # the keep/drop POLICY (the only thing you normally edit)
│   ├── allowlist.txt         # directories/files to KEEP (git-filter-repo --paths-from-file)
│   ├── droplist.txt          # proven dead-weight to DROP after the keep pass (--invert-paths)
│   ├── required.txt          # hard-fail gate: these MUST exist post-filter or the build aborts
│   ├── watch-roots.txt       # drift report scope (what to flag as upstream changes)
│   └── last-upstream-sha     # baseline SHA of the last successful sync
├── overlay/             # OUR added files, injected at the repo root (README.md + LICENSE)
└── overlay-build/       # OUR docs shipped under the repo's build/ (AGENTS.md + build README.md)
```

**What ships into the repo as `build/`:** every sync also copies the build tooling into a `build/`
folder inside the snapshot so the repo is self-reproducing — `details.md`→`build/GUIDE.md`,
`sync/` (script + vendored git-filter-repo), `filter/*.txt`, and `overlay-build/` (AGENTS.md +
build README). Like `overlay/`, this is OUR addition and is NOT part of the pristine upstream
subset. Local run-state (`last-upstream-sha`, `*.log`, drift/size reports) is NOT shipped.

## How to run a sync (monthly, or whenever upstream has a confirmed-good release)

```sh
bash sync/import-upstream.sh              # build + gates + drift report, NO push
FORCE_PUSH=1 bash sync/import-upstream.sh # also force-push the new snapshot to origin
```

What it does, in order:
1. Fresh clone of upstream into a scratch dir (`.sao-upstream-scratch/`, auto-removed).
2. Strips upstream tags, filters to `allowlist.txt`, drops `droplist.txt` paths.
3. **Gates (abort loudly on failure):** required files present; new upstream SHA is a
   descendant of the last one (detects upstream force-push); min-size floor; (replacement
   asserts — currently none).
4. **Drift report** → `last-drift-report.txt`: what changed upstream in `watch-roots.txt`
   since last sync. **If non-empty, review it** — upstream may have added/renamed a file you
   need to add to `allowlist.txt`.
5. Builds `github/` as a **single orphan commit** (snapshot, no history) = filtered tree +
   `overlay/`. Commit message records the upstream SHA for provenance.
6. gc, then (if `FORCE_PUSH=1`) force-pushes `main`.

**You only need to intervene when a gate aborts or the drift report flags something.** Normal
syncs are hands-off. Only sync upstream versions you've confirmed actually run.

## After a sync: verify it still works

The sync proves files are present; it does NOT prove mocap works. To verify (needs a webcam):
install a tiny static server + headless check, or just serve `github/` and open it:
```sh
# any static server with COOP/COEP headers + .xml as application/xml; then:
#   open http://localhost:PORT/XR_Animator.html
#   Start -> Streamer mode -> Webcam/Media -> select camera -> confirm avatar tracks you
```
(The original `smoketest/` tooling that did this automatically was removed after launch; it was
`puppeteer-core` driving Chrome with a fake camera + a COOP/COEP static server. Rebuild only if
you want automated regression checks.)

## Design decisions & GOTCHAS (every one of these cost a debug cycle — do not relearn)

- **git-filter-repo `--replace-text` treats `#` as a REDACTION trigger, NOT a comment.** A bare
  `#` makes it replace every `#` in the codebase with `***REMOVED***` (once corrupted 222 files).
  `--paths-from-file` DOES honor `#` comments; `--replace-text` does NOT. The script strips
  comments before passing a replace-text file. (There are currently no active replacements.)
- **Don't fetch upstream tags** — they pinned old-world history and bloated `.git`. Script
  strips tags pre-filter.
- **jThree (legacy renderer, 34 MB) is KEPT, not dropped.** Its `if (MMD_SA.use_jThree){...}`
  block in `MMD.js/MMD_SA.js` ALSO loads core mocap deps (OneEuroFilter, jszip, audio_BPM).
  Flipping `use_jThree=false` broke mocap. A clean drop isn't possible without editing code,
  which would break the pristine/re-syncable guarantee — so jThree stays.
- **Default scene needs small asset packs or boot stalls at 88%** (fatal zip-loader error):
  `sound/`, `images/cdungeon/item_icon.zip` (80 KB — NOT the 115 MB HDRI), `images/sprite_sheet.zip`
  (file only), `images/kiss_mark_red*.png`. Kept at file level — see `allowlist.txt`.
- **The settings/webcam menu renders AS a speech bubble** → needs `images/SB_*.png` or the
  panel is a black WebGL box (texture built from a 0-dimension failed-to-load image).
- **Dropped dead-weight (proven never fetched during tracking):** `js/@mediapipe/holistic/`,
  `js/@mediapipe/tasks/holistic_landmarker.task`, `efficient{det,net}_*`, `js/*_solution_*`
  (the legacy MediaPipe Solutions API). The 5 Tasks-vision models actually used are kept:
  face/hand/pose-full/pose-heavy `.task` + `vision_wasm_internal.wasm`. If you drop more,
  PROVE it's unused first (serve with request logging, run a full tracking session incl. the
  Pose-quality "Best" toggle which loads pose_landmarker_heavy).
- **Single-commit, history force-pushed every sync.** No upstream history is kept (the drift
  report is how we see "what's new"). Push is plain `--force` (NOT `--force-with-lease` —
  history rewrites every sync so lease always rejects "stale info"). Solo-owned repo, intentional
  rewrite — safe.
- **Known upstream limitation (not ours):** glasses degrade MediaPipe blink/eye-openness —
  inherent to `face_landmarker.task` (kept byte-identical). Affects upstream too.
- **Commit identity** is hardcoded `Ron81 <github@chaosworld.de>` in the script (the repo owner).
- **No AI-authorship references** in any committed file or commit message (owner standing rule).
  The README's disclosure that an AI runs the automation is intentional and allowed.

## Size history (for reference)

| Stage | working tree | .git | commits |
|---|---|---|---|
| upstream SAO | 698 MB | ~570 MB | 1861 |
| clutter removed | 403 MB | 310 MB | 1861 |
| + measurement trim | 205 MB | 231 MB | 1861 |
| + single-commit | **205 MB** | **97 MB** | **1** |

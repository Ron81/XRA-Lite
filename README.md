# XRA-Lite

A **slim, trimmed re-package of the XR Animator web app** from
[**ButzYung / SystemAnimatorOnline**](https://github.com/ButzYung/SystemAnimatorOnline) ("SAO").

This repository contains **only** the files needed to run the XR Animator motion-capture web
app (webcam → VRM avatar: face, hands, fingers, body, expressions). All of SAO's unrelated
legacy layers — the Windows desktop-gadget shell, Internet-Explorer/HTA/NW.js/Electron
entry points, the Dungeon RPG engine, the large HDRI/EXR environment sets, demo animation
packs, and other bundled media — have been removed.

> **This is not original work.** XRA-Lite claims **nothing** of its own. Every line of
> application code, every asset, and all functionality here is the work of
> **Butz Yung / Anime Theme** and the upstream project's third-party dependencies. XRA-Lite
> is purely a mechanical subset of that project. See **Attribution & License** below.

## Why this exists

XRA-Lite is a lean, always-current reference of just the XR Animator web app, used as a
clean baseline for other work. It is kept **pristine** — a faithful subset of upstream with
**no code changes of its own** — so it can be re-synced from upstream cheaply and repeatably.

## Size (measured)

How much of upstream this trim keeps vs. drops (tracked working tree, excluding `.git`):

| | Working tree | Files |
|---|---|---|
| Upstream SAO (original) | 704.2 MB | 1,672 |
| XRA-Lite (result) | 211.0 MB | 842 |
| Saved | 493.3 MB (70.0%) | — |

*Measured 2026-11-13 from upstream `7559f2a54856b0ef47c7db5199f0962aee8b6223` (v0.36.0). Re-measured on each sync.*

## What's IN vs OUT

**Kept** (the XR Animator web app + its runtime dependencies):

| Path | What it is |
|---|---|
| `XR_Animator.html` | the web entry point |
| `XRA_node_server.js` | SAO's tiny static file server for localhost |
| `css/` | stylesheet(s) loaded by the entry page |
| `js/` | all core app JS, the MediaPipe/Tasks ML models + WASM, mocap engine, workers |
| `three.js/` | the three.js / three-vrm renderer (the VRM pipeline) |
| `jThree/` | legacy renderer **kept intact** (see note) |
| `MMD.js/` | MMD/VRM bone-retarget + render pipeline (`MMD_SA.js`) |
| `images/XR Animator/` | the XR Animator app layer (`animate.js`, scene assets, translations) |
| `settings.html`, small root config files, default-scene asset packs | boot/runtime requirements |

**Removed** (not needed for the web mocap app):

- Legacy entry points: `SystemAnimator_ie.*`, `*_webkit.html`, `*_xul.html`, `*_cef.html`,
  `gadget.xml`-era Windows-gadget shell files, `au3/` (AutoIt), `TEMP/`.
- The Dungeon RPG assets and the large environment media: `images/cdungeon/` (HDRI/EXR),
  `images/_dungeon/`, demo animation/wallpaper subfolders, most of `sound/`-adjacent demos.
- Electron desktop wrappers and desktop-only features (VMC protocol, transparent window, etc.).

> **Note on `jThree/`:** it is a discontinued legacy renderer, but in SAO its load block also
> pulls in renderer-agnostic core dependencies the mocap app needs (motion smoothing, zip
> handling). Removing it cleanly would require editing upstream code, which XRA-Lite does not
> do. So `jThree/` is **kept as-is** to preserve the pristine, no-edits guarantee.

## How this is maintained (automation disclosure)

The trimming and the periodic re-sync from upstream are performed by an **automated process
(an AI agent orchestrating deterministic git tooling)**. To be clear about what that means:

- **No code in this repository is authored, written, or modified by an AI.** Every file is a
  byte-for-byte copy of the corresponding file in the upstream SAO repository.
- The automation **only decides which upstream files to keep or drop** (a path allowlist) and
  mechanically produces this slim repository from upstream using `git-filter-repo`.
- Because the trim is a deterministic subset, this repository's history is **rebuilt and
  force-updated** on each sync rather than appended — it always reflects a specific upstream
  commit (recorded per sync).

**Reproduce it yourself.** The build tooling ships in [`build/`](build/) — the full guide
(`build/GUIDE.md`), the sync script + vendored `git-filter-repo`, and the keep/drop policy. Like
this README and `LICENSE`, `build/` is **our** addition and is **not** part of the pristine upstream
subset. 

**Running this with an AI agent?** See [`build/AGENTS.md`](build/AGENTS.md) for the agent
runbook (how to run it, how to verify, when to stop and ask a human).

## Running it
```
node XRA_node_server.js      # serves on localhost (see the file header for the port)
```
Then open `XR_Animator.html`, use it like the original app, no changes.

## Attribution & License

**XR Animator / System Animator is © Butz Yung / Anime Theme.** All credit for the software
belongs to the original author and the upstream project.

Upstream license — this derivative is distributed under the **same** terms:

> **CC BY-NC-SA 4.0** — Creative Commons Attribution-NonCommercial-ShareAlike 4.0
> http://creativecommons.org/licenses/by-nc-sa/4.0/
>
> - Applies to adapting XR Animator's source code for your own purpose.
> - Does **not** cover third-party assets, which have their own (possibly incompatible) licenses.
> - Does **not** apply to content generated by XR Animator's functionality using your own
>   assets — the original author claims no right or responsibility over such content.

**Upstream third-party components** (credits carried from SAO, non-exhaustive): three.js,
three-vrm (pixiv), jThree v2 (GrimoireJS), ammo.js (zlib), JSZip (MIT), MediaPipe (Google),
Transformers.js (Hugging Face), bvh2vrma, osc-js, PeerJS, TensorFlow.js, and the bundled 3D
models/motions/textures credited in the upstream README. Their respective licenses apply.

For the authoritative, complete copyright/license/credits, see the upstream project:
https://github.com/ButzYung/SystemAnimatorOnline

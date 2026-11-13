#!/usr/bin/env bash
# import-upstream.sh — rebuild XRA-Lite's slim repo from upstream SystemAnimatorOnline.
#
# DETERMINISTIC, re-runnable, LLM-free in the normal path. An LLM is only needed when a GATE
# below aborts (loud, self-announcing). See the plan + README for the full rationale.
#
# Model (corrected after design review — NOT a ff-only merge):
#   fresh scratch clone -> git-filter-repo by allowlist (+ subtractive --replace-text)
#   -> GATES (required files, upstream-ancestor, min-size, neutralization asserts)
#   -> import into github/ by reset --hard  -> drift report  -> gc  -> (caller force-pushes)
#
# Usage:  sync/import-upstream.sh [UPSTREAM_SHA]
#   UPSTREAM_SHA optional; defaults to current upstream master HEAD.
# Env:    FORCE_PUSH=1 to push after a clean build (default: build only, caller inspects).
set -euo pipefail

# --- paths (this script lives in <playground>/sync/) ---
SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SYNC_DIR/.." && pwd)"            # playground root (NOT the git repo)
REPO="$ROOT/github"                            # the slim git repo (only thing that syncs)
FILTER="$ROOT/filter"
FR="python3 $SYNC_DIR/vendor/git-filter-repo"  # vendored, pinned
SCRATCH="$ROOT/.sao-upstream-scratch"          # external scratch, OUTSIDE github/
UPSTREAM_URL="https://github.com/ButzYung/SystemAnimatorOnline.git"
UPSTREAM_BRANCH="master"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[import] $*" >&2; }

# min-size floor: a healthy slim build is well above these; a catastrophic restructure trips it
MIN_FILES=50
MIN_BYTES=$((5 * 1024 * 1024))   # 5 MB

[ -d "$REPO/.git" ] || die "slim repo not initialized at $REPO"
[ -f "$FILTER/allowlist.txt" ] || die "missing $FILTER/allowlist.txt"
[ -f "$FILTER/required.txt" ]  || die "missing $FILTER/required.txt"

OLD_SHA="$(tr -d '[:space:]' < "$FILTER/last-upstream-sha" 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# 1. Fresh scratch clone (filter-repo refuses a non-fresh clone — honor it)
# ---------------------------------------------------------------------------
log "fresh scratch clone -> $SCRATCH"
rm -rf "$SCRATCH"
git clone --no-local "$UPSTREAM_URL" "$SCRATCH" >&2
NEW_SHA="${1:-$(git -C "$SCRATCH" rev-parse "$UPSTREAM_BRANCH")}"
git -C "$SCRATCH" checkout -q "$NEW_SHA"
log "upstream target SHA: $NEW_SHA"

# Measure UPSTREAM original size (tracked tree) BEFORE any filtering, so the README size table can
# report original + saved + result. Pure read; no effect on the build.
UP_FILES=$(git -C "$SCRATCH" ls-files | wc -l | tr -d ' ')
UP_BYTES=$(git -C "$SCRATCH" ls-tree -r -l HEAD | awk '{s+=$4} END{print s+0}')
log "upstream original: $UP_FILES files, $UP_BYTES bytes"

# ---------------------------------------------------------------------------
# 2. Upstream-ancestor gate (detect upstream history rewrite / force-push)
# ---------------------------------------------------------------------------
if [ -n "$OLD_SHA" ]; then
  if git -C "$SCRATCH" cat-file -e "${OLD_SHA}^{commit}" 2>/dev/null; then
    git -C "$SCRATCH" merge-base --is-ancestor "$OLD_SHA" "$NEW_SHA" \
      || die "upstream rewrote history: last SHA $OLD_SHA is NOT an ancestor of $NEW_SHA. Human review."
    log "ancestor gate OK ($OLD_SHA is ancestor of $NEW_SHA)"
  else
    log "WARN: previous SHA $OLD_SHA not found upstream (shallow? rewrite?) — skipping ancestor gate"
  fi
else
  log "no previous SHA recorded — initial build, ancestor gate skipped"
fi

# compute drift report IN SCRATCH before anything else clobbers baselines
DRIFT_OUT="$ROOT/last-drift-report.txt"
if [ -n "$OLD_SHA" ] && git -C "$SCRATCH" cat-file -e "${OLD_SHA}^{commit}" 2>/dev/null; then
  log "drift report $OLD_SHA..$NEW_SHA (watch-roots) -> $DRIFT_OUT"
  # shellcheck disable=SC2046
  git -C "$SCRATCH" diff --find-renames --name-status "$OLD_SHA" "$NEW_SHA" \
    -- $(grep -vE '^\s*#|^\s*$' "$FILTER/watch-roots.txt" | tr '\n' ' ') > "$DRIFT_OUT" 2>/dev/null || true
else
  : > "$DRIFT_OUT"
fi

# ---------------------------------------------------------------------------
# 3. Filter to the allowlist + apply subtractive --replace-text neutralizations
# ---------------------------------------------------------------------------
log "git-filter-repo: allowlist + replacements"
# Strip upstream tags BEFORE filtering: they pin old-world (pre-filter) history of excluded
# paths and are the main .git bloat. Our slim history rewrites monthly, so upstream tags are
# meaningless here anyway. Remove them so filter-repo doesn't carry their referenced objects.
git -C "$SCRATCH" tag -l | while IFS= read -r t; do [ -n "$t" ] && git -C "$SCRATCH" tag -d "$t" >/dev/null; done
REPLACE_ARGS=()
# IMPORTANT: git-filter-repo's --replace-text does NOT support '#' comments — it treats a bare
# '#' as a redaction trigger (replacing it with ***REMOVED*** across ALL files). Our
# replacements.txt is human-commented, so we MUST strip comment/blank lines into a clean temp
# file before passing it to filter-repo. (Learned the hard way: unstripped comments corrupted
# 222 files by redacting every '#'.)
CLEAN_REPLACE="$(mktemp)"
trap 'rm -f "$CLEAN_REPLACE"' EXIT
grep -vE '^\s*#|^\s*$' "$FILTER/replacements.txt" > "$CLEAN_REPLACE" 2>/dev/null || true
if [ -s "$CLEAN_REPLACE" ]; then
  REPLACE_ARGS=(--replace-text "$CLEAN_REPLACE")
  log "replacements: $(wc -l < "$CLEAN_REPLACE" | tr -d ' ') rule(s) (comments stripped)"
fi
( cd "$SCRATCH" && $FR --force \
    --paths-from-file "$FILTER/allowlist.txt" \
    ${REPLACE_ARGS[@]+"${REPLACE_ARGS[@]}"} ) >&2

# Drop-pass: remove proven dead-weight that the coarse allowlist kept (measurement-driven;
# see filter/droplist.txt). Uses --invert-paths so listed paths are REMOVED. Each entry becomes
# --path (exact/prefix) or --path-glob (if it starts with 'glob:'). '#' comments stripped.
if [ -f "$FILTER/droplist.txt" ] && grep -qvE '^\s*#|^\s*$' "$FILTER/droplist.txt"; then
  DROP_ARGS=()
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | sed 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    case "$line" in
      glob:*) DROP_ARGS+=(--path-glob "${line#glob:}") ;;
      *)      DROP_ARGS+=(--path "$line") ;;
    esac
  done < "$FILTER/droplist.txt"
  if [ "${#DROP_ARGS[@]}" -gt 0 ]; then
    log "drop-pass: removing $(( ${#DROP_ARGS[@]} / 2 )) proven dead-weight path(s)"
    ( cd "$SCRATCH" && $FR --force --invert-paths "${DROP_ARGS[@]}" ) >&2
  fi
fi

# ---------------------------------------------------------------------------
# 4. GATES against the filtered tree
# ---------------------------------------------------------------------------
log "gate: required files present"
MISSING=0
while IFS= read -r f; do
  [ -z "$f" ] && continue; case "$f" in \#*) continue;; esac
  if ! git -C "$SCRATCH" cat-file -e "HEAD:$f" 2>/dev/null; then
    echo "  MISSING required: $f" >&2; MISSING=1
  fi
done < "$FILTER/required.txt"
[ "$MISSING" -eq 0 ] || die "required-files gate failed (upstream moved/renamed something). Human review."

log "gate: subtractive neutralization asserts"
# For each `literal:OLD==>NEW` rule: NEW must be present, OLD must be absent in the filtered tree.
while IFS= read -r rule; do
  case "$rule" in ""|\#*) continue;; esac
  [ "${rule#literal:}" = "$rule" ] && continue
  body="${rule#literal:}"; OLDSTR="${body%%==>*}"; NEWSTR="${body#*==>}"
  [ "$OLDSTR" = "$NEWSTR" ] && continue
  # `git grep` exits 1 on no-match; under pipefail that would wrongly abort. Guard with `|| true`
  # and count lines explicitly so a zero-match (the desired state for OLD) is a value, not a failure.
  present_new=$(git -C "$SCRATCH" grep -F -l "$NEWSTR" HEAD 2>/dev/null || true); present_new=$(printf '%s' "$present_new" | grep -c . || true)
  present_old=$(git -C "$SCRATCH" grep -F -l "$OLDSTR" HEAD 2>/dev/null || true); present_old=$(printf '%s' "$present_old" | grep -c . || true)
  [ "${present_new:-0}" -ge 1 ] || die "neutralization assert: replacement string absent -> '$NEWSTR' (anchor moved?). Human review."
  [ "${present_old:-0}" -eq 0 ] || die "neutralization assert: original string still present -> '$OLDSTR'. Human review."
  log "  neutralization OK: '$OLDSTR' -> '$NEWSTR'"
done < "$FILTER/replacements.txt"

log "gate: min-size floor"
NFILES=$(git -C "$SCRATCH" ls-files | wc -l | tr -d ' ')
NBYTES=$(git -C "$SCRATCH" ls-tree -r -l HEAD | awk '{s+=$4} END{print s+0}')
[ "$NFILES" -ge "$MIN_FILES" ] || die "min-size floor: only $NFILES files (< $MIN_FILES). Catastrophic filter? Human review."
[ "$NBYTES" -ge "$MIN_BYTES" ] || die "min-size floor: only $NBYTES bytes (< $MIN_BYTES). Human review."
log "  size OK: $NFILES files, $NBYTES bytes"

# ---------------------------------------------------------------------------
# 5. Import as a SINGLE orphan commit — snapshot only, NO upstream history.
# We don't want 10 years of upstream history: the monthly diff/drift report tells us what's new,
# and we only pull confirmed-working snapshots. A single commit means .git ≈ the tree (no old
# versions of kept files), clones are cheap, and it matches the "pristine snapshot, rewritten
# monthly" model. Provenance is preserved via the recorded upstream SHA (in the commit message).
# ---------------------------------------------------------------------------
log "import: single-commit snapshot of the filtered tree into $REPO"
ORIGIN_URL="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
# Export the filtered scratch's working tree (checked out, clean) as our snapshot source.
git -C "$SCRATCH" checkout -q -- . 2>/dev/null || true
SNAP="$(mktemp -d)"
# copy the scratch's tracked tree (NOT its .git) into a staging dir, then add our overlay
git -C "$SCRATCH" archive --format=tar HEAD | ( cd "$SNAP" && tar -xf - )
OVERLAY="$ROOT/overlay"
if [ -d "$OVERLAY" ] && [ -n "$(ls -A "$OVERLAY" 2>/dev/null)" ]; then
  cp -R "$OVERLAY"/. "$SNAP"/
fi

# Stage OUR build tooling into the snapshot under build/ so the repo is self-reproducing: anyone
# cloning gets the guide, the agent runbook, the sync script + vendored git-filter-repo, and the
# filter policy. This is deliberately NOT part of the pristine upstream subset (like README/LICENSE).
# The live source of truth stays at the playground root; build/ is a shipped copy. Local run-state
# (last-upstream-sha, *.log, drift report, empty patches/, .DS_Store) is intentionally excluded.
log "stage build/ tooling into snapshot"
mkdir -p "$SNAP/build/sync/vendor" "$SNAP/build/filter"
cp "$ROOT/details.md"                      "$SNAP/build/GUIDE.md"
cp "$SYNC_DIR/import-upstream.sh"          "$SNAP/build/sync/import-upstream.sh"
cp "$SYNC_DIR/vendor/git-filter-repo"      "$SNAP/build/sync/vendor/git-filter-repo"
for p in allowlist droplist required replacements watch-roots; do
  [ -f "$FILTER/$p.txt" ] && cp "$FILTER/$p.txt" "$SNAP/build/filter/$p.txt"
done
OVERLAY_BUILD="$ROOT/overlay-build"   # AGENTS.md + build/README.md source (our docs, not generated)
if [ -d "$OVERLAY_BUILD" ]; then
  cp -R "$OVERLAY_BUILD"/. "$SNAP/build/"
fi

# Rebuild github/.git from empty + commit the snapshot as the ONE and only commit.
rm -rf "$REPO/.git"
# move the staged tree into place (replace working files), preserving nothing stale
find "$REPO" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true
cp -R "$SNAP"/. "$REPO"/
rm -rf "$SNAP"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -B main
git -C "$REPO" add -A >&2
GIT_AUTHOR_NAME="Ron81" GIT_AUTHOR_EMAIL="github@chaosworld.de" \
GIT_COMMITTER_NAME="Ron81" GIT_COMMITTER_EMAIL="github@chaosworld.de" \
  git -C "$REPO" commit -q -m "XRA-Lite — slim snapshot of SystemAnimatorOnline @ $NEW_SHA

Trimmed, pristine extract of the XR Animator web app (see README).
Mechanical subset of upstream commit $NEW_SHA — no history retained by design;
rebuilt from upstream each sync. See filter/ in the build tooling for the keep/drop policy." >&2
[ -n "$ORIGIN_URL" ] && git -C "$REPO" remote add origin "$ORIGIN_URL"

# record the new baseline SHA (lives in playground filter/, NOT committed to the slim repo)
echo "$NEW_SHA" > "$FILTER/last-upstream-sha"

# ---------------------------------------------------------------------------
# 6. Reclaim space so the slim claim is real + measurable
# ---------------------------------------------------------------------------
log "gc: expire reflog + prune"
git -C "$REPO" reflog expire --expire=now --all >&2 2>/dev/null || true
git -C "$REPO" update-ref -d refs/imports/upstream-slim 2>/dev/null || true
git -C "$REPO" gc --prune=now >&2
REPO_GIT_SIZE=$(du -sh "$REPO/.git" | cut -f1)
log "slim .git size: $REPO_GIT_SIZE"

# ---------------------------------------------------------------------------
# 7. Report / optional push
# ---------------------------------------------------------------------------
echo
echo "=== IMPORT COMPLETE ==="
echo "upstream: $OLD_SHA -> $NEW_SHA"
# saved = upstream original tree - slim tree (both tracked bytes, pre-.git)
SAVED_BYTES=$(( UP_BYTES - NBYTES ))
SAVED_PCT=$(awk "BEGIN{ if ($UP_BYTES>0) printf \"%.1f\", 100*$SAVED_BYTES/$UP_BYTES; else print \"0\" }")
UP_MB=$(awk "BEGIN{printf \"%.1f\", $UP_BYTES/1048576}")
SLIM_MB=$(awk "BEGIN{printf \"%.1f\", $NBYTES/1048576}")
SAVED_MB=$(awk "BEGIN{printf \"%.1f\", $SAVED_BYTES/1048576}")
echo "upstream original: $UP_FILES files, $UP_MB MB ($UP_BYTES bytes)"
echo "slim result:       $NFILES files, $SLIM_MB MB ($NBYTES bytes), .git $REPO_GIT_SIZE"
echo "saved:             $SAVED_MB MB ($SAVED_PCT%)"
echo "drift report: $DRIFT_OUT ($([ -s "$DRIFT_OUT" ] && wc -l < "$DRIFT_OUT" || echo 0) lines)"
# machine-readable stamp for README size-table updates (playground-local, not committed to slim repo)
printf 'upstream_sha=%s\nup_files=%s\nup_bytes=%s\nup_mb=%s\nslim_files=%s\nslim_bytes=%s\nslim_mb=%s\nsaved_mb=%s\nsaved_pct=%s\n' \
  "$NEW_SHA" "$UP_FILES" "$UP_BYTES" "$UP_MB" "$NFILES" "$NBYTES" "$SLIM_MB" "$SAVED_MB" "$SAVED_PCT" \
  > "$ROOT/last-size-report.txt"
if [ "${FORCE_PUSH:-0}" = "1" ]; then
  # Plain --force (NOT --force-with-lease): every sync REWRITES history by design, so lease
  # always rejects with "stale info". Safe here — solo-owned private repo, intentional rewrite.
  git -C "$REPO" remote get-url origin >/dev/null 2>&1 \
    && { log "force-pushing main"; git -C "$REPO" push --force -u origin main >&2; } \
    || log "no 'origin' remote yet — skipping push"
else
  echo "(build only; set FORCE_PUSH=1 to push, or inspect $REPO first)"
fi
rm -rf "$SCRATCH"

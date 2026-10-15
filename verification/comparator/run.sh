#!/usr/bin/env bash
# Re-run the comparator check (https://github.com/leanprover/comparator) on this tree. Linux (bash, git, python3, GNU coreutils).
# Prerequisite: the tree is fully built ('lake build' at the repository root, Mathlib included; the wrapper reuses those .olean files).
# What it does: fetches comparator and lean4export at the pinned tags, pins both to this repository's lean-toolchain, builds them from otherwise
# unchanged source, creates a wrapper Lake project holding Challenge.lean / Solution.lean whose build directory is a symlink farm of the tree's
# compiled products, and runs 'lake env comparator config.json' there. Exit code = comparator's; its standard output goes to
# $WORK/wrapper/comparator.log, whose last line is 'Your solution is okay!' on success.
# Resources: about 15 h of wall time, nearly all of it the kernel replay on one core (about 13 h); peak resident memory about 230 GB during
# the replay (allow 300 GB).
# Knobs (environment): WORK (default .verify-work at the repository root), COMPARATOR_SRC / LEAN4EXPORT_SRC (existing source checkouts to reuse;
# step 2 still pins their lean-toolchain and comparator's lakefile), COMPARATOR_REV / LEAN4EXPORT_REV (tag or branch, default v4.33.0),
# VMEM_GB (per-process address-space cap, default 640), LEAN_NUM_THREADS (default 4), LANDRUN (path to a landrun binary - untested with this
# layout, whose build directory symlinks outside the wrapper; without one, comparator's own scripts/fake-landrun.sh is used = no sandbox, which is
# how the recorded run was made; the sandbox guards against an untrusted solution, which is moot when you built the tree yourself).
set -euo pipefail
shopt -s nullglob
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/verification/comparator
WORK=${WORK:-$ROOT/.verify-work}; mkdir -p "$WORK/src"; WORK=$(cd "$WORK" && pwd)
COMPARATOR_REV=${COMPARATOR_REV:-v4.33.0}; LEAN4EXPORT_REV=${LEAN4EXPORT_REV:-v4.33.0}
VMEM_GB=${VMEM_GB:-640}
TOOLCHAIN=$(cat "$ROOT/lean-toolchain")
log(){ printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }

# 1. sources (pre-existing checkouts are reused; step 2 still pins their lean-toolchain and comparator's lakefile)
CMP=${COMPARATOR_SRC:-$WORK/src/comparator}; EXP=${LEAN4EXPORT_SRC:-$WORK/src/lean4export}
[ -d "$EXP" ] || git clone --depth 1 --branch "$LEAN4EXPORT_REV" https://github.com/leanprover/lean4export "$EXP"
[ -d "$CMP" ] || git clone --depth 1 --branch "$COMPARATOR_REV" https://github.com/leanprover/comparator "$CMP"
CMP=$(cd "$CMP" && pwd); EXP=$(cd "$EXP" && pwd)
# 2. pin both tools to the tree's toolchain; make comparator build against this lean4export checkout instead of fetching one
echo "$TOOLCHAIN" > "$EXP/lean-toolchain"; echo "$TOOLCHAIN" > "$CMP/lean-toolchain"
if ! grep -qF "path = \"$EXP\"" "$CMP/lakefile.toml"; then
  python3 - "$CMP/lakefile.toml" "$EXP" <<'EOF'
import re, sys
p, exp = sys.argv[1], sys.argv[2]; t = open(p).read()
blocks = re.split(r'(?m)^(?=\[\[)', t)   # drop the [[require]] table for lean4export, then require it by path
keep = [b for b in blocks if not (b.startswith('[[require]]') and re.search(r'name\s*=\s*"lean4export"', b))]
open(p, 'w').write(''.join(keep).rstrip('\n') + '\n\n[[require]]\nname = "lean4export"\npath = "%s"\n' % exp)
EOF
  rm -f "$CMP/lake-manifest.json"
fi
# 3. build the two tools
log "building lean4export ($LEAN4EXPORT_REV) and comparator ($COMPARATOR_REV) on $TOOLCHAIN"
( cd "$EXP" && lake build lean4export )
( cd "$CMP" && lake build comparator )
EXPBIN=$EXP/.lake/build/bin/lean4export; CMPBIN=$CMP/.lake/build/bin/comparator
mkdir -p "$WORK/bin"; ln -sfn "$EXPBIN" "$WORK/bin/lean4export"
if [ -n "${LANDRUN:-}" ]; then ln -sfn "$LANDRUN" "$WORK/bin/landrun"
elif command -v landrun >/dev/null 2>&1; then ln -sfn "$(command -v landrun)" "$WORK/bin/landrun"
else chmod +x "$CMP/scripts/fake-landrun.sh"; ln -sfn "$CMP/scripts/fake-landrun.sh" "$WORK/bin/landrun"
     log "WARNING: no landrun found - using comparator's scripts/fake-landrun.sh (NO sandbox around the solution's build)"; fi
# 4. wrapper project: the four input files + a symlink farm of every compiled library root of the tree
W=$WORK/wrapper; mkdir -p "$W/.lake/build/lib/lean"
cp "$HERE/Challenge.lean" "$HERE/Solution.lean" "$HERE/lakefile.toml" "$HERE/config.json" "$W/"; echo "$TOOLCHAIN" > "$W/lean-toolchain"
[ -e "$ROOT/.lake/build/lib/lean/Theorems" ] || { log "ERROR: $ROOT/.lake/build/lib/lean/Theorems missing - run 'lake build' at the repository root first"; exit 2; }
for r in "$ROOT/.lake/build/lib/lean" "$ROOT"/.lake/packages/*/.lake/build/lib/lean; do
  for e in "$r"/*; do b=$W/.lake/build/lib/lean/$(basename "$e")
    if [ -L "$b" ] && [ "$(readlink "$b")" = "$e" ]; then continue; fi
    ln -sn "$e" "$b" 2>/dev/null || { log "ERROR: name collision in the symlink farm: $e (existing $(readlink "$b")). Use a fresh WORK directory."; exit 2; }; done; done
[ -e "$W/.lake/build/lib/lean/Mathlib.olean" ] || { log "ERROR: Mathlib.olean not found under $ROOT/.lake/packages - is the tree built?"; exit 2; }
# 5. run
cd "$W"; unset LEAN_PATH
export PATH=$WORK/bin:$PATH LEAN_NUM_THREADS=${LEAN_NUM_THREADS:-4} MIMALLOC_GENERIC_COLLECT=${MIMALLOC_GENERIC_COLLECT:-1000000} LEAN_ABORT_ON_PANIC=1
{ echo "START $(date -u +%FT%TZ) toolchain=$TOOLCHAIN vmem=${VMEM_GB}GiB threads=$LEAN_NUM_THREADS"
  echo "lean: $(lean --version 2>&1)"
  echo "comparator $(git -C "$CMP" rev-parse HEAD 2>/dev/null || echo '?') bin=$(sha256sum "$CMPBIN" | cut -c1-16); lean4export $(git -C "$EXP" rev-parse HEAD 2>/dev/null || echo '?') bin=$(sha256sum "$EXPBIN" | cut -c1-16); landrun -> $(readlink -f "$WORK/bin/landrun")"
  echo "tree $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo '?') dirty=$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -vc '^?? ' || true)"
  echo "inputs:"; sha256sum Challenge.lean Solution.lean lakefile.toml config.json lean-toolchain; } > run.status
log "running comparator in $W (log: $W/comparator.log)"
set +e
( ulimit -v $((VMEM_GB*1024*1024)); stdbuf -oL -eL lake env "$CMPBIN" config.json 2> comparator.err | tee comparator.log; exit "${PIPESTATUS[0]}" )
rc=$?
set -e
echo "END $(date -u +%FT%TZ) rc=$rc" >> run.status
log "comparator exit code $rc; last line: $(tail -n 1 comparator.log)"
exit $rc

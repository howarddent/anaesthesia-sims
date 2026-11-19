#!/usr/bin/env bash
# This file is part of anaesthesia-sims.
# Copyright (C) 2026 Howard Dent
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build a redistributable binary of one project:
#
#   release/build-release.sh [--working-tree] <path/to/Project.lpi>
#
# 1. Stage a clean copy of the sources in a temporary directory: the
#    committed HEAD of this repo and of the newVM submodule (git archive), or
#    with --working-tree the tracked files as they are now, for testing
#    uncommitted changes. Nothing in the working tree is touched.
# 2. Refuse to go on if any kernel include (<name>_cl.inc beside <name>.cl)
#    is stale - see tools/cl2inc.py.
# 3. Put release/newVMConfig.release.inc in place of the staged
#    newVM/newVMConfig.inc, so nothing is linked at build time.
# 4. Build with lazbuild: GTK2 on Linux, Cocoa on macOS, Win32 on Windows.
# 5. Check the binary's direct library dependencies, failing if it links
#    MKL, IPP, OpenBLAS, FFTW, ArmPL, OpenCL or clFFT (OpenCL must be loaded
#    at run time, so that the program can start without it and say so).
#
# The binary lands in release/out/<os>-<cpu>/. Lazarus is found at $LAZDIR
# (default ~/Lazarus; on the mac it is "~/lazarus 2").
set -euo pipefail

WORKTREE=0
if [ "${1:-}" = --working-tree ]; then WORKTREE=1; shift; fi
[ $# -eq 1 ] || { sed -n '6,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LPI_REL=$1
[ -f "$ROOT/$LPI_REL" ] || { echo "no such project: $LPI_REL" >&2; exit 2; }
LAZDIR=${LAZDIR:-$HOME/Lazarus}
[ -x "$LAZDIR/lazbuild" ] || [ -x "$LAZDIR/lazbuild.exe" ] || {
  echo "lazbuild not found in $LAZDIR (set LAZDIR)" >&2; exit 2; }

case "$(uname -s)" in
  Linux)   OS=linux;   WS=gtk2 ;;
  Darwin)  OS=macos;   WS=cocoa ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows; WS=win32 ;;
  *) echo "unsupported platform $(uname -s)" >&2; exit 2 ;;
esac
CPU=$(uname -m); [ "$CPU" = arm64 ] && CPU=aarch64
OUT="$ROOT/release/out/$OS-$CPU"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/anaesthesia-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

echo "== staging sources in $STAGE"
if [ $WORKTREE = 1 ]; then
  (cd "$ROOT" && git ls-files -z --recurse-submodules | tar --null -T - -cf - | tar -xf - -C "$STAGE")
  echo "   (working tree, uncommitted changes included)"
else
  (cd "$ROOT" && git archive HEAD | tar -xf - -C "$STAGE")
  (cd "$ROOT/newVM" && git archive HEAD | tar -xf - -C "$STAGE/newVM")
  echo "   anaesthesia-sims $(git -C "$ROOT" rev-parse --short HEAD), newVM $(git -C "$ROOT/newVM" rev-parse --short HEAD)"
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "   warning: the working tree has uncommitted changes, which are NOT in this build"
  fi
fi

PROJ_DIR=$(dirname "$STAGE/$LPI_REL")
echo "== checking kernel includes"
shopt -s nullglob
for cl in "$PROJ_DIR"/*.cl; do
  inc="${cl%.cl}_cl.inc"
  [ -f "$inc" ] || continue
  const=$(sed -n 's/^  \([A-Za-z0-9_]*\) =$/\1/p' "$inc" | head -1)
  python3 "$ROOT/tools/cl2inc.py" --check "$cl" "$inc" "$const" || {
    echo "   regenerate it: python3 tools/cl2inc.py $(basename "$cl") $(basename "$inc") $const" >&2
    exit 1; }
  echo "   $(basename "$inc") matches $(basename "$cl")"
done

echo "== release config"
cp "$ROOT/release/newVMConfig.release.inc" "$STAGE/newVM/newVMConfig.inc"

echo "== lazbuild ($WS)"
LAZBUILD="$LAZDIR/lazbuild"; [ -x "$LAZBUILD" ] || LAZBUILD="$LAZDIR/lazbuild.exe"
if ! "$LAZBUILD" --lazarusdir="$LAZDIR" --ws=$WS --build-mode=Default -B "$STAGE/$LPI_REL" > "$STAGE/lazbuild.log" 2>&1; then
  grep -iE "error|fatal" "$STAGE/lazbuild.log" | head -20 >&2
  exit 1
fi
NAME=$(basename "$LPI_REL" .lpi)
BIN="$PROJ_DIR/$NAME"; [ -f "$BIN" ] || BIN="$BIN.exe"
[ -f "$BIN" ] || { echo "built, but $BIN is missing" >&2; exit 1; }

echo "== direct library dependencies"
case $OS in
  linux)   DEPS=$(readelf -d "$BIN" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p') ;;
  macos)   DEPS=$(otool -L "$BIN" | tail -n +2 | awk '{print $1}') ;;
  windows) DEPS=$(objdump -p "$BIN" 2>/dev/null | sed -n 's/.*DLL Name: //p' || true) ;;
esac
echo "$DEPS" | sed 's/^/   /'
BAD=$(echo "$DEPS" | grep -iE 'mkl|ipp|openblas|fftw|armpl|opencl|clfft' || true)
if [ -n "$BAD" ]; then
  echo "links libraries a user may not have:" >&2; echo "$BAD" | sed 's/^/   /' >&2
  exit 1
fi

mkdir -p "$OUT"
cp "$BIN" "$OUT/"
echo "== $OUT/$(basename "$BIN")"

#!/usr/bin/env bash
# check.sh — fast typecheck of individual modules during development.
#
# `cabal build` cannot run until every module listed in backend-hs.cabal
# exists and compiles, which is awkward while the port is being written
# module by module. This script typechecks whatever files you name (or all
# of src/ by default) against the already-built dependency closure, with
# the same extensions the .cabal file sets.
#
#   ./check.sh                       # everything under src/
#   ./check.sh src/Graph.hs          # just one module
#
# Once the port is complete, prefer `cabal build` — it is the real check.
set -euo pipefail
cd "$(dirname "$0")"

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(find src app -name '*.hs' | sort)
fi

mkdir -p dist-newstyle/packagedb/ghc-9.4.7
exec cabal exec -- ghc -fno-code -isrc -iapp \
  -XGHC2021 -XDerivingStrategies -XLambdaCase -XOverloadedStrings \
  -Wall -Wcompat -Wredundant-constraints \
  "${files[@]}"

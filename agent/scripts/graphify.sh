#!/usr/bin/env bash
# Offline codebase graph (ADR-013). Runs a pinned graphifyy release and allows only commands that parse this
# repository locally: no LLM, no network source, no global graph, no git hook, no assistant install.
# Code is parsed with tree-sitter on this machine. Output goes to graphify-out/, which is gitignored.
set -euo pipefail

GRAPHIFY_VERSION="0.9.104"
ALLOWED="extract update cluster-only query path explain god-nodes affected"

cd "$(dirname "$0")/.."

if ! command -v uvx >/dev/null 2>&1; then
  echo "graphify: uvx is required (install uv: https://docs.astral.sh/uv/)" >&2
  exit 2
fi

sub="${1:-}"
if [[ -z "$sub" ]]; then
  echo "usage: scripts/graphify.sh <$ALLOWED> [args]" >&2
  exit 2
fi
case " $ALLOWED " in
  *" $sub "*) ;;
  *) echo "graphify: '$sub' is not allowed here (ADR-013). Allowed: $ALLOWED" >&2; exit 2 ;;
esac

has_flag() {
  local flag="$1"; shift
  local arg
  for arg in "$@"; do
    [[ "$arg" == "$flag" ]] && return 0
  done
  return 1
}

if [[ "$sub" == "extract" ]] && ! has_flag "--code-only" "$@"; then
  echo "graphify: extract must pass --code-only (no LLM, docs are not sent anywhere)" >&2
  exit 2
fi

args=("$@")
if [[ "$sub" == "cluster-only" ]] && ! has_flag "--no-label" "$@"; then
  args+=("--no-label")
fi

export GRAPHIFY_BACKEND=none
exec uvx --quiet --from "graphifyy==${GRAPHIFY_VERSION}" graphify "${args[@]}"

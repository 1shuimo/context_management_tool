#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESEARCH_DIR="$ROOT_DIR/research"
MODE="${1:-pinned}"

mkdir -p "$RESEARCH_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required but not found in PATH" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  bash scripts/bootstrap_research.sh
  bash scripts/bootstrap_research.sh pinned
  bash scripts/bootstrap_research.sh latest

Modes:
  pinned  Clone/fetch repos and checkout the exact commits referenced by the notes.
  latest  Clone/fetch repos and leave them on the remote default branch HEAD.
EOF
}

case "$MODE" in
  pinned|latest)
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown mode '$MODE'" >&2
    usage
    exit 1
    ;;
esac

sync_repo() {
  local name="$1"
  local url="$2"
  local commit="$3"
  local target="$RESEARCH_DIR/$name"

  if [ ! -d "$target/.git" ]; then
    echo "clone: $url -> $target"
    git clone "$url" "$target"
  else
    echo "found: $target"
  fi

  if [ -n "$(git -C "$target" status --porcelain)" ]; then
    echo "warn: $name has local changes; skipping checkout/update to avoid overwriting work" >&2
    return 0
  fi

  echo "fetch: $name"
  git -C "$target" fetch --all --tags --prune

  if [ "$MODE" = "latest" ]; then
    local default_branch
    default_branch="$(git -C "$target" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
    if [ -z "$default_branch" ]; then
      default_branch="main"
    fi
    echo "checkout: $name -> origin/$default_branch"
    git -C "$target" checkout "$default_branch" >/dev/null 2>&1 || git -C "$target" checkout -B "$default_branch" "origin/$default_branch"
    git -C "$target" reset --hard "origin/$default_branch" >/dev/null
    return 0
  fi

  echo "checkout: $name -> $commit"
  git -C "$target" checkout --detach "$commit" >/dev/null
}

sync_repo "context-mode" "https://github.com/mksglu/context-mode.git" "3469b7ab422afc0323bfde76ba67c80f7fbe8570"
sync_repo "Context-Gateway" "https://github.com/Compresr-ai/Context-Gateway.git" "810171ef2b6348a915baa9bf76a2801f6249d92b"
sync_repo "headroom" "https://github.com/chopratejas/headroom.git" "3945c02aa5a1dcbb25bc5b3b39d3684ef38d0d49"
sync_repo "rtk" "https://github.com/rtk-ai/rtk.git" "b11fb00cde0d8759de563d602c2e3952be482309"
sync_repo "ctx-zip" "https://github.com/karthikscale3/ctx-zip.git" "76580f7ba1555c891928702743ac74412c7fac60"
sync_repo "ReMe" "https://github.com/agentscope-ai/ReMe.git" "f408d6ec4a6141aeddd3a76f943bcec83714a503"
sync_repo "deepagents" "https://github.com/langchain-ai/deepagents.git" "eb0b26c9578c8ed9f20aea3b2d8b852af1a4a6ac"
sync_repo "letta" "https://github.com/letta-ai/letta.git" "4cb2f21c65d571d807d7466335e51432826749ba"
sync_repo "mem0" "https://github.com/mem0ai/mem0.git" "34c797d2850c33b45ec28d6f8748bda05473b637"

echo
if [ "$MODE" = "latest" ]; then
  echo "research workspace synced to latest remote default branches under: $RESEARCH_DIR"
else
  echo "research workspace synced to the note-pinned commits under: $RESEARCH_DIR"
fi

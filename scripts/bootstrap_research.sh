#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESEARCH_DIR="$ROOT_DIR/research"

mkdir -p "$RESEARCH_DIR"

clone_if_missing() {
  local url="$1"
  local target="$2"

  if [ -d "$target/.git" ]; then
    echo "skip: $target"
    return 0
  fi

  echo "clone: $url -> $target"
  git clone "$url" "$target"
}

clone_if_missing "https://github.com/mksglu/context-mode.git" "$RESEARCH_DIR/context-mode"
clone_if_missing "https://github.com/Compresr-ai/Context-Gateway.git" "$RESEARCH_DIR/Context-Gateway"
clone_if_missing "https://github.com/chopratejas/headroom.git" "$RESEARCH_DIR/headroom"
clone_if_missing "https://github.com/rtk-ai/rtk.git" "$RESEARCH_DIR/rtk"
clone_if_missing "https://github.com/karthikscale3/ctx-zip.git" "$RESEARCH_DIR/ctx-zip"
clone_if_missing "https://github.com/agentscope-ai/ReMe.git" "$RESEARCH_DIR/ReMe"
clone_if_missing "https://github.com/langchain-ai/deepagents.git" "$RESEARCH_DIR/deepagents"
clone_if_missing "https://github.com/letta-ai/letta.git" "$RESEARCH_DIR/letta"
clone_if_missing "https://github.com/mem0ai/mem0.git" "$RESEARCH_DIR/mem0"

echo
echo "research workspace ready under: $RESEARCH_DIR"

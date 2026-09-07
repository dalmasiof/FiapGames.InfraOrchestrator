#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

repos=(
  "FiapGame.AuthService"
  "FiapGame.PaymentService"
  "FiapGames.Catalog"
)

command -v docker >/dev/null 2>&1 || {
  echo "Error: docker is not installed or not in PATH." >&2
  exit 1
}

echo "Bootstrap: validating workspace at $ROOT_DIR..."
for repo_name in "${repos[@]}"; do
  repo_path="$ROOT_DIR/$repo_name"
  if [[ ! -d "$repo_path" ]]; then
    echo "Error: repository not found: $repo_path" >&2
    exit 1
  fi
done

cd "$SCRIPT_DIR"
docker compose config --quiet
docker compose up -d --build

echo "Local API environment started successfully."

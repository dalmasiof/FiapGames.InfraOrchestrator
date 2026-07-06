#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="/c/git/FiapGames_MS"

repos=(
  "FiapGame.AuthService"
  "FiapGame.PaymentService"
  "FiapGames.Catalog"
  "FiapGames.Notification"
)

function require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Erro: '$1' não está instalado ou não está no PATH." >&2
    exit 1
  }
}

require_tool docker
require_tool docker-compose

echo "Bootstrap: validando workspace em $ROOT_DIR..."
if [[ ! -d "$ROOT_DIR" ]]; then
  echo "Erro: workspace não encontrado em $ROOT_DIR" >&2
  exit 1
fi

for repo_name in "${repos[@]}"; do
  repo_path="$ROOT_DIR/$repo_name"
  if [[ ! -d "$repo_path" ]]; then
    echo "Erro: repositório ausente: $repo_path" >&2
    exit 1
  fi
done

cd "$SCRIPT_DIR"
docker compose up -d --build

echo "Aplicação orquestrada iniciada com sucesso."

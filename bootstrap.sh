#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

declare -A repos
repos[FiapGame.AuthService]="$ROOT_DIR/FiapGame.AuthService"
repos[FiapGame.PaymentService]="$ROOT_DIR/FiapGame.PaymentService"
repos[FiapGames.Catalog]="$ROOT_DIR/FiapGames.Catalog"
repos[FiapGames.Notification]="$ROOT_DIR/FiapGames.Notification"

function require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Erro: '$1' não está instalado ou não está no PATH." >&2
    exit 1
  }
}

require_tool git
require_tool docker
require_tool docker-compose

for repo_name in "${!repos[@]}"; do
  repo_path="${repos[$repo_name]}"
  if [[ ! -d "$repo_path" ]]; then
    echo "Aviso: repositório local não encontrado: $repo_name ($repo_path)"
    echo "  Crie o diretório manualmente ou ajuste o caminho no bootstrap.sh"
    continue
  fi

  if [[ -d "$repo_path/.git" ]]; then
    echo "Atualizando $repo_name..."
    git -C "$repo_path" pull --ff-only
  else
    echo "Aviso: $repo_name existe, mas não é um repositório Git. Pulando atualização."
  fi
 done

cd "$SCRIPT_DIR"
docker compose up -d --build

echo "Aplicação orquestrada iniciada com sucesso."

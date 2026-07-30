#!/usr/bin/env bash
# Roda a cada (re)início do Codespace. Só imprime as URLs públicas e o atalho de
# subida — o provisionamento pesado é do post-create. Nada aqui é destrutivo.
set -euo pipefail

if [ -n "${CODESPACE_NAME:-}" ]; then
  DOMAIN="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  echo ""
  echo "───────────────────────────────────────────────────────────────"
  echo " RoboTrack no Codespace"
  echo "   App (abra esta):  https://${CODESPACE_NAME}-5173.${DOMAIN}"
  echo "   API (Rails):      https://${CODESPACE_NAME}-3000.${DOMAIN}"
  echo ""
  echo "   Subir o app:      bash .devcontainer/scripts/dev.sh"
  echo "   Claude Code:      claude"
  echo "───────────────────────────────────────────────────────────────"
  echo ""
fi

#!/usr/bin/env bash
# Sobe o RoboTrack no Codespace: Rails API (:3000) + Vite (:5173), com as URLs
# públicas certas. UM comando — é o que você roda no dia a dia.
#
# Estratégia same-origin: VITE_API_URL e VITE_WS_URL apontam para a PRÓPRIA
# origem do frontend (-5173), e o proxy do Vite (vite.config.codespaces.ts)
# encaminha /api, /cable, /users… para o Rails :3000. Assim não há CORS nem
# dependência da porta 3000 estar pública.
set -euo pipefail

cd "$(dirname "$0")/../.."   # raiz do repositório
ROOT="$(pwd)"

if [ -n "${CODESPACE_NAME:-}" ]; then
  DOMAIN="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  FRONT="https://${CODESPACE_NAME}-5173.${DOMAIN}"
  export VITE_API_URL="$FRONT"
  export VITE_WS_URL="${FRONT/https:/wss:}"
  export CORS_ORIGINS="$FRONT"
  echo "▸ Frontend público: $FRONT"
else
  echo "▸ Fora do Codespace — usando localhost (proxy padrão)."
fi

# Encerra os dois processos juntos ao sair (Ctrl-C).
cleanup() { trap - EXIT INT TERM; kill 0 2>/dev/null || true; }
trap cleanup EXIT INT TERM

echo "▸ Subindo Rails API em :3000…"
( cd "$ROOT/backend" && exec bundle exec rails s -b 0.0.0.0 -p 3000 ) &

echo "▸ Subindo Vite em :5173…"
( cd "$ROOT/frontend" && exec npx vite --host --port 5173 --config vite.config.codespaces.ts ) &

wait

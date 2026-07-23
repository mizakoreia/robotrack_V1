#!/usr/bin/env bash
set -euo pipefail

# Smoke pós-deploy do staging (delivery-and-observability 2.4). Sobe a stack sobre
# a imagem de produção, espera o release rodar as migrations e o web ficar
# healthy, e afirma 200 em /health/ready. Um Procfile com processo faltando ou uma
# migration que não roda reprovam AQUI, não no primeiro deploy real.
#
# HANDOFF: exige um daemon Docker (ausente no ambiente efêmero de CI atual).
# Registrar a execução no runbook quando um runner com Docker existir.

COMPOSE="docker compose -f docker-compose.staging.yml"

cleanup() { $COMPOSE down -v >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "[smoke] subindo a stack de staging…"
$COMPOSE up -d --build

echo "[smoke] aguardando o web ficar healthy…"
for i in $(seq 1 40); do
  status=$($COMPOSE ps web --format '{{.Health}}' 2>/dev/null || echo '')
  [ "$status" = "healthy" ] && break
  sleep 3
done

echo "[smoke] afirmando 200 em /health/ready…"
code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/health/ready)
if [ "$code" != "200" ]; then
  echo "[smoke] FALHOU: /health/ready respondeu $code"
  $COMPOSE logs web release
  exit 1
fi
echo "[smoke] OK: /health/ready = 200"

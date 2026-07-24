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

# Despeja TODO o estado e reprova. Sem isto o smoke já mentiu: quando o web não
# subia, o curl caía no dev server do HOST na :3000 e reportava 200 (falso
# positivo). Agora afirmamos de DENTRO da rede do compose (`exec web`) e, ao
# falhar, imprimimos ps + logs de release/web/worker pra o par ter o motivo cru.
dump_and_fail() {
  echo "[smoke] FALHOU: $1"
  echo "----- docker compose ps -a -----"
  $COMPOSE ps -a || true
  echo "----- logs: release -----"
  $COMPOSE logs release || true
  echo "----- logs: web -----"
  $COMPOSE logs web || true
  echo "----- logs: worker -----"
  $COMPOSE logs worker || true
  exit 1
}

echo "[smoke] subindo a stack de staging…"
$COMPOSE up -d --build

echo "[smoke] aguardando o web ficar healthy…"
healthy=false
for _ in $(seq 1 40); do
  # Se o container já MORREU (exited), não adianta esperar o timeout inteiro —
  # o release falhou ou o boot do web abortou. Reprova na hora com os logs.
  # `ps` sem `-a` NÃO lista container parado (devolvia string vazia e a
  # detecção precoce nunca disparava — feedback do par); `-a` inclui os mortos.
  state=$($COMPOSE ps -a web --format '{{.State}}' 2>/dev/null || echo '')
  if [ "$state" = "exited" ]; then
    dump_and_fail "o container web morreu (state=exited) antes de ficar healthy"
  fi
  status=$($COMPOSE ps web --format '{{.Health}}' 2>/dev/null || echo '')
  if [ "$status" = "healthy" ]; then
    healthy=true
    break
  fi
  sleep 3
done
[ "$healthy" = true ] || dump_and_fail "o web nunca ficou healthy dentro do tempo limite"

echo "[smoke] afirmando 200 em /health/ready (de DENTRO da rede do compose)…"
# Afirma via `exec web`: bate no próprio web pelo loopback do container, não na
# :3000 do host. Assim o smoke não pode confundir o web real com um dev server
# que por acaso escute na mesma porta do host (ACHADO 1 — o falso positivo).
code=$($COMPOSE exec -T web curl -s -o /dev/null -w '%{http_code}' \
  http://localhost:3000/health/ready || echo '000')
[ "$code" = "200" ] || dump_and_fail "/health/ready respondeu $code (esperado 200)"
echo "[smoke] OK: /health/ready = 200"

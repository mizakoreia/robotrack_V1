# Handoff de `design-system` → `delivery-and-observability` (tarefa 8.4)

Nota deixada por `design-system`. Requisitos de **CSP de produção** para a base
visual funcionar. Sem eles, o Inter não carrega e o script anti-FOUC é bloqueado —
devolvendo o flash de tema errado que ele existe para eliminar.

## Content-Security-Policy — o que a base visual exige

| Diretiva | Valor | Por quê |
|---|---|---|
| `style-src` | inclui `https://fonts.googleapis.com` | o `<link>` do Inter (index.html 3.1) |
| `font-src` | inclui `https://fonts.gstatic.com` | os arquivos da fonte Inter |
| `script-src` | o **hash** do script anti-FOUC inline (NÃO `unsafe-inline`) | o script síncrono de 4.2 que aplica `.light` antes da hidratação |

- O `<link>` do Google Fonts usa `font-display: swap`: se a CSP bloquear, o texto
  segue legível na fallback stack (`Inter, system-ui, …`) — o contraste medido
  continua válido, mas a escala tipográfica quebra. Então isto é correção de
  qualidade, não de disponibilidade.
- O script anti-FOUC é inline por necessidade (roda antes de qualquer bundle).
  Prefira o **hash** em `script-src` a `unsafe-inline` (que abriria toda a
  superfície). O conteúdo do script está em `frontend/index.html`.

## Métrica de frame (7.5) — alvo do seu job de perf

`design-system` trava a parte DETERMINÍSTICA da luz ambiente (throttle ≤ 32
escritas/1000ms; a `.ambient` não altera token de texto/fundo, logo o contraste é
idêntico com a luz ligada e com `data-glow="off"`). O **p50 de duração de frame**
com 24 cards em tela (luz ligada vs. `data-glow="off"`) é medição de HARDWARE e
pertence ao seu job de perf: o p50 com a luz ligada deve ser igual à linha de base
(a luz não pode custar leitura).

## O que já está pronto do lado de `design-system`

- Token set único (dois temas) em `globals.css`; contraste medido no CI
  (`tests/contrast.test.ts`); tema não segue o esquema do sistema (guarda de CI).
- 9 primitivos em `components/ui/` + `Icon`/sprite; luz ambiente com 3 degradações.
- Recharts/TipTap/Slate desinstalados; guarda que impede o retorno
  (`tests/no-heavy-deps.test.ts`). Bundle principal caiu ~208 kB.

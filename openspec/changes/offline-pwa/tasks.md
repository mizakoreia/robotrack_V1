## 1. Fundação de armazenamento (pré-requisito de tudo)

- [x] 1.1 Criar `frontend/src/lib/storage/safeStorage.ts` com `get`/`set`/`remove` em `try/catch`, adapter em memória, e a sonda de boot que classifica o nível em `persistent` / `session-only` / `memory-only` antes da primeira renderização (§4.2 — `setItem` lançando `QuotaExceededError` devolve `false` sem propagar exceção; com `localStorage` lançando e `sessionStorage` funcional o nível é `session-only`, não `persistent`)
- [x] 1.2 Converter `lib/api/client.ts`, `authStore` e `themeStore` para usar exclusivamente o `safeStorage`, e ligar a regra ESLint `no-restricted-globals` para os três globais fora de `lib/storage/` (§4.2 — um `localStorage.getItem` introduzido em um componente novo falha o pipeline, não passa por revisão)
- [x] 1.3 Implementar o aviso persistente e dispensável-por-sessão para `session-only` e `memory-only`, com as duas redações de pt-BR de D7-11 (§4.2 — em `memory-only` o aviso inclui a frase sobre alterações offline não serem salvas; em `session-only`, não)
- [x] 1.4 **Verificação:** teste de integração que simula os três níveis com os globais lançando e afirma que o login conclui nos três (§4.2 — login em janela privada navega para a Visão Geral, sem tela branca e sem exceção não capturada no console)

## 2. Service worker (§4.3)

- [x] 2.1 Escrever `frontend/public/sw.js` com `install`/`skipWaiting` e `activate` apagando todo cache diferente do corrente mais o prefixo legado `robotrack-v9-`, seguido de `clients.claim()` (§4.3 — dispositivo com o PWA legado instalado deixa de servir o `index.html` antigo do cache `robotrack-v9-cache-v25`)
- [x] 2.2 Implementar o guard de não-interceptação: retornar sem `respondWith` para método ≠ GET, para `pathname` casando `^/(api|auth|cable|rails/active_storage)/`, e para origem diferente (§4.3 — `GET /api/v1/robots` same-origin offline **falha**, não responde do cache)
- [x] 2.3 Implementar a estratégia network-first same-origin (gravando só respostas `ok`) e o fallback de navegação para `/index.html` em cache (§4.3 — resposta `503` da rede não sobrescreve a cópia válida em cache, e `/projetos/P/celulas/C/robos/R` aberta offline devolve 200)
- [x] 2.4 Injetar `CACHE_NAME` a partir do hash do build via plugin do Vite, registrar o SW no boot com aviso de "nova versão disponível" em `controllerchange`, e configurar `Cache-Control: no-cache, must-revalidate` para `/sw.js` no servidor de assets, citando `delivery-and-observability` (§4.3 — `HEAD /sw.js` no ambiente publicado não retorna `max-age` maior que zero, e aba aberta durante um deploy exibe o aviso em vez de continuar em código antigo)
- [x] 2.5 **Verificação:** suíte de `FetchEvent` sintéticos para `/api/v1/robots`, `POST` same-origin, navegação offline e asset em cache, afirmando por caso se `respondWith` foi chamado (§4.3 — o caso `/api/v1/robots` afirma que `respondWith` **não** foi chamado, e falha se alguém adicionar uma rota de cache de API)

## 3. Fila de mutations: esquema e persistência (§4.2)

- [x] 3.1 Criar o banco IndexedDB `robotrack` com object store `mutations` (`keyPath: id`, `seq` autoincremental), índices `by_state_and_seq` e `by_workspace`, store auxiliar `resolved_uuids`, e `onupgradeneeded` versionado com quarentena de item irreconhecível (§4.2 — item gravado por esquema anterior e não migrável vai para `failed` classe "incompatível", nunca é apagado)
- [x] 3.2 Implementar `enqueueMutation` com `depends_on` obrigatório no tipo (sem default) e carimbo de `recorded_at` no instante da confirmação do usuário (D8 — um hook novo que esqueça `depends_on` não compila em TypeScript)
- [x] 3.3 Implementar o teto de 500 itens / 5 MB com rejeição na entrada e poda de itens `done`, e o store Zustand da fila como projeção reativa do IndexedDB escopada por `workspace_id` (§4.2/D9 — com 500 pendentes a 501ª é rejeitada e o item mais antigo **não** é descartado; a fila de `W1` não aparece nem é enviada na UI de `W2`)
- [x] 3.4 **Verificação:** teste com `fake-indexeddb` cobrindo reabertura, ordem de `seq` e poda (§4.2 — após drenar 200 de 500, a contagem é exatamente 300 e novas mutations voltam a ser aceitas)

## 4. Fila: grafo de dependência e drenagem (D7-4)

- [x] 4.1 Implementar o cálculo de elegibilidade por `depends_on` contra `resolved_uuids`, pulando itens não elegíveis sem bloquear os posteriores (§4.2 — `project.rename` de `seq` 4 sobe enquanto `task.create` de `seq` 2 espera pelo robô)
- [x] 4.2 Implementar o povoamento de `resolved_uuids` a partir de respostas 2xx e de uuids lidos do servidor (D1 — tarefa criada offline contra um robô que já existia no servidor é elegível sem depender de nenhuma mutation de criação)
- [x] 4.3 Implementar o laço de drenagem sequencial por `seq` restrito pelo grafo, com uma requisição em voo por vez, e os gatilhos (`online`, `visibilitychange`, foco, sucesso, timer de 30s) filtrados pela sonda `HEAD /api/v1/health` (§4.2 — Wi-Fi de galpão sem rota de saída dispara uma sonda, não 40 requisições)
- [x] 4.4 **Verificação:** E2E do cenário canônico com rede cortada — criar robô `R`, tarefa `T`, avanço `A`, restaurar rede, afirmar a ordem das três chamadas no servidor (§4.2 — se a ordem inverter, `T` recebe 422 por FK ausente e o teste falha; ele não pode passar por acidente)

## 5. Fila: idempotência, erro e poison message (D7-5, D7-6)

- [ ] 5.1 Implementar a classificação de resposta em retryable / permanente / conflito / autenticação conforme a tabela de D7-5, incluindo `DELETE` com 404 tratado como sucesso (§4.2 — 403 por revogação de papel vai direto para `failed` sem consumir as 8 tentativas, e reenvio de exclusão já aplicada não enche a quarentena)
- [ ] 5.2 Implementar backoff `min(2^attempts × 1s, 5min)` com jitter de ±20%, teto de 8 tentativas retryable, e a pausa global da fila em 401 sem incremento de `attempts` (§4.2 — 500 repetido oito vezes encerra o reenvio em vez de drenar a bateria em laço; token expirado não queima as 8 tentativas do item em voo)
- [ ] 5.3 Implementar a cascata de bloqueio: item permanente vai para `failed`, o fechamento transitivo dos dependentes vai para `blocked`, e os independentes continuam drenando (§4.2 — `robot.create` com 422 e 5 dependentes atrás não impede que as 2 mutations independentes cheguem a `done`)
- [ ] 5.4 Implementar a UI de reconciliação com "Corrigir e reenviar" e "Descartar N alterações" (contagem do fechamento transitivo no rótulo) e o caminho de 409 de `lock_version`, que entra nela sem reenvio automático (§4.2/§2.4 — o botão diz "Descartar 6 alterações" quando há 1 falho e 5 bloqueados; avanço conflitante não é reenviado em laço contra um `lock_version` que nunca vai casar)
- [ ] 5.5 **Verificação:** teste de tabela cobrindo cada linha da matriz de D7-5, mais o teste de replay duplicado (§4.2 — a mesma `advance.create A` entregue duas vezes produz uma linha em `task_advances` e progresso 30, não 60)

## 6. Coordenação entre abas (D7-10)

- [ ] 6.1 Implementar a eleição de líder por `navigator.locks.request('robotrack-queue-drain', {mode: 'exclusive'})` em volta do laço de drenagem (§4.2 — três abas abertas produzem uma única requisição por mutation quando a rede volta)
- [ ] 6.2 Implementar o fan-out de transições por `BroadcastChannel('robotrack-queue')` com hidratação do store nas abas não-líderes, e o fallback (registro `leader` em IndexedDB com `expires_at` renovado a cada 5s, polling de 30s), com toda escrita de `attempts` em transação `readwrite` (§4.2 — enfileirar na aba A atualiza o indicador de B e C sem recarregar; duas abas disputando a liderança numa janela de expiração não fazem `attempts` pular de 3 para 8)
- [ ] 6.3 **Verificação:** teste multi-contexto com duas instâncias compartilhando o mesmo IndexedDB, contando requisições no servidor (§4.2 — o servidor recebe exatamente 1 requisição para a mutation, não 2)

## 7. Sobreposição otimista e indicador honesto (D7-7)

- [ ] 7.1 Implementar a função pura `overlay(serverData, pendingMutations)` cobrindo criação de robô, criação de tarefa e avanço de progresso (§2.2 — avanço pendente de 50 → 60 aplicado sobre `serverData` com 50 produz 60, e o status derivado vira `Em Andamento`)
- [ ] 7.2 Ligar a `overlay` ao `select` dos hooks de leitura de `robot-task-table` e `hierarchy-screens`, garantindo precedência sobre refetch e sobre evento do `WorkspaceChannel`, sem `setQueryData` otimista (D6/D9 — evento ao vivo invalidando a query e trazendo 50 do servidor não faz a UI piscar de 60 para 50 em nenhum quadro)
- [ ] 7.3 Ligar o produtor do indicador de gravação ao contrato de `app-shell-navigation`, acrescentando `pendente` e `bloqueado`, e desligar a fila em `memory-only` com mutation indo direto à rede (§4.2 — com um item na fila o indicador exibe `pendente`, nunca `salvo`; em `memory-only` mostra `erro` e **não** cria item prometendo envio posterior)
- [ ] 7.4 **Verificação:** teste da sequência enfileirar → evento do canal → refetch com dado antigo → asserção de que o valor exibido permanece o otimista em todos os quadros (§4.2 — o teste falha se a implementação usar snapshot em memória, porque o remount entre os passos o destrói)

## 8. Sessão, convite e prova de ponta a ponta

- [ ] 8.1 Ligar a escolha do meio de armazenamento da sessão ao "manter conectado" e ao nível da sonda, com aviso quando a marcação não puder ser honrada, e migrar `robotrack.theme` para `safeStorage` aplicado antes da primeira pintura (§4.2/§5.1 — "manter conectado" em `session-only` conclui o login e explica por quê; sistema em modo claro sem preferência gravada abre o app em escuro)
- [ ] 8.2 Migrar a captura e o consumo do token de convite para `sessionStorage` via `safeStorage`, com remoção após o consumo e detecção do convite perdido em `memory-only` instruindo a reabrir o link (D4.4 — o convite não é perdido em silêncio; o link de uso único ainda não foi consumido e reabri-lo funciona)
- [ ] 8.3 **Backup obrigatório antes de 8.4:** implementar a exportação da fila para JSON, baixável pela UI de diagnóstico, executada antes de qualquer migração de esquema do IndexedDB (§4.2 — uma migração que quarentene itens ainda deixa o usuário recuperar o conteúdo do avanço registrado às 14h)
- [ ] 8.4 Implementar a migração de esquema versionada do IndexedDB, executada só depois de 8.3 (§4.2 — abrir uma versão nova sobre uma base antiga não perde item pendente algum)
- [ ] 8.5 Escrever o E2E de honestidade temporal e o E2E de deploy (§4.3/D8 — avanço confirmado offline às 14:03 e sincronizado às 17:41 exibe 14:03 na trilha e no relatório com `created_at` 17:41; e nenhum asset do build A é servido do cache após publicar o build B com rede disponível)
- [ ] 8.6 **Verificação:** rodar a suíte E2E offline completa em Chromium e WebKit e registrar os resultados no runbook de `delivery-and-observability` (§4.2/§4.3 — o caminho de fallback sem Web Locks é exercitado no WebKit, não só assumido correto)

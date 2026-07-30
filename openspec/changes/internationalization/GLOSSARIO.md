# GLOSSÁRIO pt-BR → EN — ✅ CONFIRMADO PELO DONO

> **PORTÃO LIBERADO.** O dono revisou e **aprovou** os termos (execução autorizada).
> As 7 decisões que estavam em aberto foram fixadas assim (aplicadas no código):
>
> 1. **Avanço / Registrar avanço → Progress update / Log progress** ✅
> 2. **Protocolo de Comissionamento → Commissioning Protocol** ✅
> 3. **Concluído → Done (tela) / Completed (relatório)** ✅
> 4. **Progresso físico → Task completion** (correção do dono; NÃO "Physical progress") ✅
> 5. **Categoria E → Trajectories** (confirmado; NÃO "Paths") ✅
> 6. **Solda Ponto / Solda MIG → Spot Welding / MIG Welding** ✅
> 7. **31 tarefas-base, 9 categorias e aplicações → como propostas abaixo** ✅
> **Todos os demais termos → aprovados.** As marcas ⚠️ abaixo ficam como histórico da
> dúvida (já resolvida), não como pendência.
>
> **Regra dura de arquitetura (vale para todo este glossário):** os valores de
> **status**, as **6 aplicações de robô** e as **31 tarefas-base / 9 categorias**
> estão **gravados no banco em pt-BR** (enum `task_status`, CHECK de `robots.application`,
> linhas de `task_templates` semeadas por workspace). A importação do legado casa por
> texto (`desc`). Portanto o EN é **camada de EXIBIÇÃO** — um mapa `pt-BR → EN`
> resolvido na tela — **nunca** um rename do dado. Traduzir o dado quebraria o CHECK,
> o enum e a importação legada. Isto não é negociável; a coluna do glossário "EN
> proposto" é o rótulo mostrado, não o valor persistido.

Legenda: ✅ tradução direta, baixa dúvida · ⚠️ **precisa da confirmação do dono** ·
🔒 valor gravado no banco (EN só de exibição).

---

## 1. Hierarquia (entidades)

| pt-BR | EN proposto | Nota |
|---|---|---|
| Workspace | Workspace | ✅ já em inglês no produto |
| Projeto | Project | ✅ |
| Célula | Cell | ✅ (célula de manufatura/robótica) |
| Robô | Robot | ✅ |
| Tarefa | Task | ✅ |
| Visão Geral | Overview | ✅ |
| Minhas Tarefas | My Tasks | ✅ |
| Relatório | Report | ✅ |

## 2. Progresso — as DUAS métricas nomeadas (D15, não podem se confundir)

| pt-BR | EN proposto | Nota |
|---|---|---|
| Progresso ponderado | Weighted progress | ⚠️ confirmar: "Weighted progress" vs "Weighted completion". O termo que aparece no relatório assinado precisa ser o que o dono usa com o cliente. |
| Progresso físico (tarefas concluídas) | **Task completion** ✅ | Decisão nº 4 do dono (NÃO "Physical progress"). |
| Avanço / Registrar avanço | **Progress update / Log progress** ✅ | Decisão nº 1 do dono. |
| Progresso | Progress | ✅ |
| Anel de progresso | Progress ring | ✅ |

## 3. Comissionamento

| pt-BR | EN proposto | Nota |
|---|---|---|
| Comissionamento | Commissioning | ✅ termo padrão da indústria |
| Protocolo de Comissionamento | Commissioning Protocol | ⚠️ o documento é ASSINADO. Alternativas comuns na indústria automotiva: "Commissioning Report", "Acceptance Protocol", "Commissioning Certificate". **Qual o dono usa com o cliente?** |
| Relatório de comissionamento | Commissioning report | ✅ (título da seção de ajuda) |
| Responsável / Responsáveis | Assignee / Assignees | ⚠️ no app = pessoa atribuída à tarefa. Mas o painel "Responsáveis" nas Configurações = "pessoas a quem se atribui tarefa". "Assignee" (tarefa) vs "Team member"/"Person in charge" (painel). Confirmar o par. |
| Comissionador | Commissioner | ⚠️ bloco de assinatura. Alternativa: "Commissioning engineer". Confirmar. |
| Cliente / Aceite | Client / Acceptance | ✅ |

## 4. Papéis (roles)

| pt-BR | EN proposto | Nota |
|---|---|---|
| Dono | Owner | ✅ |
| Editor / Pode editar | Editor / Can edit | ✅ |
| Visualizador / Pode visualizar | Viewer / Can view | ✅ |

(Os identificadores de banco `owner`/`edit`/`view` **não** mudam — já em inglês.)

## 5. Notificações & convites

| pt-BR | EN proposto | Nota |
|---|---|---|
| Seguir / Seguindo | Follow / Following | ✅ |
| Silenciar / Silenciado | Mute / Muted | ✅ |
| Padrão | Default | ✅ |
| Convite | Invitation (ação: Invite) | ✅ |
| Código de convite | Invite code | ✅ |
| Equipe / Membros | Team / Members | ✅ |
| Convites pendentes | Pending invitations | ✅ |

## 6. Navegação & chrome

| pt-BR | EN proposto | Nota |
|---|---|---|
| Ajuda | Help | ✅ |
| Configurações | Settings | ✅ |
| Enviar feedback | Send feedback | ✅ |
| Aparência | Appearance | ✅ |
| Tarefas-base | Base tasks (catálogo → Task catalog) | ⚠️ "Base tasks" vs "Template tasks" vs "Task catalog". Confirmar o rótulo. |
| Aplicação / Aplicações | Application / Applications | ✅ |
| Aplicação do robô | Robot application | ✅ |

## 7. Status da tarefa 🔒 (enum `task_status` — gravado em pt-BR)

| pt-BR (valor no banco) | EN de EXIBIÇÃO proposto | Nota |
|---|---|---|
| `Pendente` | Pending | ✅ |
| `Em Andamento` | In Progress | ✅ |
| `Concluído` | Done | ⚠️ "Done" (curto, legível de luva, casa com o ✓) vs "Completed" (mais formal para o relatório). O relatório usa símbolo `✓`. Confirmar se UI="Done" e relatório="Completed", ou um só. |
| `N/A` | N/A | ✅ universal |

🔒 **Nunca** renomear o enum. O EN é um `Record<statusPtBR, string>` na tela. Há um
CHECK `done-implies-100` amarrado ao valor `Concluído` — mexer no dado quebra a
invariante.

## 8. Aplicações de robô 🔒 (`Robot::APPLICATIONS`, CHECK no banco — 6 literais)

| pt-BR (valor no banco) | EN de EXIBIÇÃO proposto | Nota |
|---|---|---|
| `Misto / Geral` | Mixed / General | ✅ (o "vale para todas" — filtro "Todas as aplicações" → "All applications") |
| `Solda Ponto` | Spot Welding | ⚠️ "Spot weld"/"Spot Welding". Confirmar. |
| `Solda MIG` | MIG Welding | ⚠️ confirmar (MIG/MAG?). |
| `Handling` | Handling | ✅ já em inglês |
| `Sealing` | Sealing | ✅ já em inglês |
| `Outros` | Others | ✅ |

## 9. As 9 CATEGORIAS 🔒 (prefixo `A.`–`I.` vive DENTRO do valor, ordena por `COLLATE "C"`)

O prefixo de ordenação **permanece** no dado; o EN traduz só a parte após o ponto,
como exibição. **Todas ⚠️ para conferência do dono** (são termos de comissionamento).

| pt-BR (valor no banco) | EN de EXIBIÇÃO proposto | Nota |
|---|---|---|
| `A. Hardware` | A. Hardware | ✅ |
| `B. Rede` | B. Network | ✅ |
| `C. Segurança` | C. Safety | ✅ |
| `D. Processo` | D. Process | ✅ |
| `E. Trajetórias` | E. Trajectories (ou Paths) | ⚠️ robótica: "Paths" é comum no chão. Confirmar. |
| `F. Interlocks` | F. Interlocks | ✅ já em inglês |
| `G. Tryout` | G. Tryout | ✅ já em inglês |
| `H. Otimização` | H. Optimization | ✅ |
| `I. Aceitação` | I. Acceptance | ✅ |

## 10. As 31 TAREFAS-BASE 🔒 — **o harvest mais crítico** (o dono é o especialista)

> Os `desc` em pt-BR estão gravados **com os erros de grafia do legado de propósito**
> (`Traj, de Descarte`, `Otimização de Trajetoria`, `Robo`, `Automatico`, `ate`) — a
> importação casa por texto e "corrigir" duplicaria itens. O EN **não** precisa
> reproduzir o erro (é exibição), mas a **coluna pt-BR abaixo é o valor imutável**.
> **Todas as linhas ⚠️** — proponho, mas o dono confirma o vocabulário de robótica.

### A. Hardware
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Power On | Power On | ✅ |
| Mastering Check | Mastering Check | ⚠️ mastering/zeramento do robô — manter em EN? |
| Montagem de Ferramenta | Tool Mounting | ⚠️ "Tool Mounting"/"Tooling Assembly" |
| Check de Ferramenta/Umbilical | Tool/Umbilical Check | ⚠️ |

### B. Rede
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Config. Endereço de IP | IP Address Config | ⚠️ |
| Rede Principal | Main Network | ✅ |
| Sub Rede | Subnet | ✅ |

### C. Segurança
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Definir Cubos e esferas de segurança | Define Safety Cubes and Spheres | ⚠️ zonas de segurança — "cubes and spheres" literal; confirmar termo do fabricante (ex.: safety zones). |
| Self Check de segurança do Robo | Robot Safety Self-Check | ⚠️ |

### D. Processo
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| TCP Check | TCP Check | ✅ |
| Calibração de Frame | Frame Calibration | ✅ |
| Payload | Payload | ✅ |
| Calibração de Cola *(Sealing)* | Adhesive/Glue Calibration | ⚠️ cordão de sealing — "Adhesive" vs "Glue". Confirmar. |
| Check sinais de Gripper *(Handling, Solda Ponto)* | Gripper Signals Check | ⚠️ |

### E. Trajetórias
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Carregar OLP | Load OLP | ⚠️ OLP = offline program(ming). Expandir? |
| Teach Traj. Sem Peça | Teach Path — No Part | ⚠️ |
| Teach Traj. Com Peça | Teach Path — With Part | ⚠️ |
| Carregar Parâmetros | Load Parameters | ✅ |
| Traj, de Descarte *(grafia legada)* | Scrap/Reject Path | ⚠️ o que é "descarte" aqui — trajetória de rejeito? Confirmar. |
| Manutenção | Maintenance | ✅ |

### F. Interlocks
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| PLC-ROB interlocks/Sinais | PLC-Robot Interlocks/Signals | ✅ |

### G. Tryout
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Dryrun Baixa velocidade ate 100% *(grafia legada)* | Dry Run — Low Speed up to 100% | ⚠️ |
| Dryrun Diferentes velocidades | Dry Run — Various Speeds | ⚠️ |
| Automatico baixa velocidade *(grafia legada)* | Automatic — Low Speed | ⚠️ |
| Speed up | Speed Up | ✅ |

### H. Otimização
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Medição de Tempo de Ciclo Com peça | Cycle Time Measurement — With Part | ⚠️ |
| Otimização de Trajetoria *(grafia legada)* | Path/Trajectory Optimization | ⚠️ |

### I. Aceitação
| pt-BR (banco) | EN proposto | Nota |
|---|---|---|
| Check de aceitação interna | Internal Acceptance Check | ✅ |
| Check de aceitação do cliente | Client Acceptance Check | ✅ |
| Treinamento ao cliente | Client Training | ✅ |
| Acompanhamento | Follow-up (support) | ⚠️ "Acompanhamento" — follow-up? on-site support? Confirmar. |

## 11. Jargão técnico avulso (para consistência entre telas)

| pt-BR / termo | EN proposto | Nota |
|---|---|---|
| Ferramenta | Tool / Tooling | ⚠️ manter consistente com "Montagem de Ferramenta" |
| Umbilical | Umbilical | ✅ |
| Gripper / garra | Gripper | ✅ |
| TCP | TCP | ✅ |
| Frame | Frame | ✅ |
| Peça | Part / Workpiece | ⚠️ "Part" vs "Workpiece" |
| Dry run | Dry Run | ✅ |
| Tempo de Ciclo | Cycle Time | ✅ |
| Trajetória | Path / Trajectory | ⚠️ ver categoria E |
| Cola | Adhesive / Glue | ⚠️ ver "Calibração de Cola" |
| chão de fábrica / galpão | shop floor | ✅ (contexto de ajuda) |

---

## Decisões do dono (FECHADAS — aplicadas no código)

1. **"Avanço" → Progress update / "Registrar avanço" → Log progress** ✅
2. **"Protocolo de Comissionamento" → Commissioning Protocol** ✅
3. **"Concluído" → Done (tela) / Completed (relatório)** ✅
4. **Progresso físico → Task completion** (NÃO "Physical progress") ✅
5. **Categoria E "Trajetórias" → Trajectories** (NÃO "Paths"; as tarefas de E usam
   "Trajectory", não "Path", no mapa de exibição) ✅
6. **31 tarefas-base / 9 categorias / aplicações → como propostas neste glossário** ✅
7. **Solda Ponto / Solda MIG → Spot Welding / MIG Welding** ✅

Todos os demais termos aprovados. Regra de ouro mantida: **status, aplicações e
tarefas-base seguem gravados em pt-BR no banco; o EN é rótulo de EXIBIÇÃO** (mapa
`pt-BR → EN` na tela, D-I4), nunca rename de dado.

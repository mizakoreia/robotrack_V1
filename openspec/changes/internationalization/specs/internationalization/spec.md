## ADDED Requirements

### Requirement: Idiomas suportados e default

O sistema SHALL suportar exatamente dois idiomas — **pt-BR** e **en** — e SHALL adotar
**pt-BR como default** em toda superfície (primeira visita, storage bloqueado, usuário
sem preferência gravada). O sistema SHALL NOT expor um terceiro idioma nem seleção
automática por geolocalização.

#### Scenario: Primeira visita cai em pt-BR

- **WHEN** um visitante abre o app pela primeira vez, sem `rt-lang` no storage e sem
  conta
- **THEN** a UI é renderizada em pt-BR
- **AND** `document.documentElement.lang` é `pt-BR`

#### Scenario: Locale desconhecido não é aceito

- **WHEN** um `PATCH` tenta gravar `users.locale = 'es'`
- **THEN** o CHECK `locale IN ('pt-BR','en')` do banco rejeita

### Requirement: Seletor de idioma é um controle acessível, com bandeira não-emoji

O sistema SHALL oferecer um **controle** de idioma (nunca um badge) que permite
escolher entre Português (Brasil) e English (UK), apresentando a bandeira como
**ícone/asset SVG — nunca emoji**. O controle SHALL ter `aria-label` "Idioma /
Language", SHALL nomear cada opção por extenso, SHALL ter alvo de toque **≥ 40px**, e
SHALL manter a bandeira como decorativa (`aria-hidden`), com o **nome acessível sendo o
idioma**. O controle SHALL aparecer no menu da conta, no painel Aparência e na tela de
entrada.

#### Scenario: Bandeira emoji é reprovada pelo CI

- **WHEN** o seletor usa um caractere emoji de bandeira (`🇧🇷`/`🇬🇧`, regional-indicator)
- **THEN** `frontend/tests/no-emoji.test.ts` reprova o build

#### Scenario: O nome acessível é o idioma, não a bandeira

- **WHEN** um leitor de tela foca o gatilho do seletor
- **THEN** o nome anunciado contém "Idioma / Language" (e a opção, o idioma por
  extenso)
- **AND** a bandeira não é anunciada (é `aria-hidden`)

#### Scenario: A escolha troca a UI e o atributo lang

- **WHEN** o usuário escolhe "English (UK)" no seletor
- **THEN** a UI passa a renderizar em en
- **AND** `document.documentElement.lang` passa a `en`

### Requirement: Persistência da preferência por dispositivo e por conta

O sistema SHALL persistir a preferência de idioma **por dispositivo** em
`localStorage['rt-lang']` (com a mesma degradação do tema quando o storage está
bloqueado — vale só na sessão) e, para um usuário autenticado, SHALL espelhá-la na
coluna **`users.locale`**, que segue a pessoa entre dispositivos.

#### Scenario: Preferência sobrevive ao reload no mesmo dispositivo

- **WHEN** o usuário escolhe en e recarrega a página
- **THEN** a UI volta em en (lido de `rt-lang`)

#### Scenario: Storage bloqueado degrada para a sessão

- **WHEN** o storage está bloqueado (modo privado) e o usuário escolhe en
- **THEN** a UI fica em en durante a sessão
- **AND** um aviso informa que a escolha vale só nesta sessão

#### Scenario: Conta carrega a preferência em outro dispositivo

- **WHEN** um usuário com `users.locale = 'en'` entra num dispositivo novo, sem
  `rt-lang`
- **THEN** a UI abre em en

### Requirement: Cada pessoa só altera o próprio locale

O sistema SHALL permitir que cada usuário altere **apenas o próprio** `users.locale`.
Um usuário SHALL NOT alterar o locale de outra pessoa.

#### Scenario: Alterar o próprio locale é permitido

- **WHEN** um usuário autenticado envia `PATCH /users/me` com `locale = 'en'`
- **THEN** o `users.locale` dele passa a `en`

#### Scenario: Alterar o locale de outra pessoa é negado

- **WHEN** um usuário tenta alterar o `locale` de outro usuário
- **THEN** a operação é negada pela política (não há rota que aceite alterar locale
  alheio)

### Requirement: Dado de domínio é traduzido só na exibição, nunca no banco

O sistema SHALL manter gravados em pt-BR os valores de `task_status`, as 6 aplicações
de `Robot::APPLICATIONS` e as linhas de `task_templates` (`cat`/`desc`), e SHALL
apresentar o EN como **camada de exibição** mapeada pelo valor pt-BR. O sistema SHALL
NOT renomear o enum, o CHECK de aplicação ou os `desc` do catálogo para traduzir.

#### Scenario: O valor persistido do status continua pt-BR

- **WHEN** o app está em en e uma tarefa está `Concluído`
- **THEN** a UI exibe o rótulo EN correspondente (ex.: "Done")
- **AND** o valor gravado na coluna `status` continua `Concluído`
- **AND** o CHECK `done-implies-100` continua válido

#### Scenario: A grafia legada do catálogo é preservada

- **WHEN** o app está em en e mostra a tarefa-base cujo `desc` gravado é
  `Traj, de Descarte`
- **THEN** a UI exibe o rótulo EN de exibição
- **AND** o `desc` gravado permanece `Traj, de Descarte` (a importação legada casa por
  ele)

### Requirement: Notificação é congelada no locale do destinatário

O sistema SHALL renderizar e congelar `notifications.msg` **no locale do
DESTINATÁRIO** no momento do INSERT (não mais em pt-BR fixo), preservando o
congelamento por linha e a imutabilidade (só `read`/`read_at` mudam).

#### Scenario: Destinatário en recebe a notificação em en

- **WHEN** uma tarefa avança e o destinatário tem `users.locale = 'en'`
- **THEN** a `msg` congelada na linha dele está em en

#### Scenario: Dois destinatários, dois idiomas, na mesma emissão

- **WHEN** o mesmo avanço notifica uma pessoa pt-BR e uma pessoa en
- **THEN** cada linha é congelada no idioma do seu destinatário

#### Scenario: Trocar de idioma não reescreve notificações antigas

- **WHEN** um usuário com notificações antigas em pt-BR muda para en
- **THEN** as notificações antigas continuam em pt-BR (congeladas), e as novas nascem
  em en

### Requirement: Auditoria congela no locale do ator e permanece imutável

O sistema SHALL renderizar e congelar `audit_logs.msg` **no locale do ATOR** no INSERT,
e SHALL manter a trilha **append-only e imutável** (REVOKE UPDATE/DELETE + trigger + RLS
+ guarda de boot + snapshot de CI). O sistema SHALL NOT reescrever linhas históricas
para trocar o idioma.

#### Scenario: Registro nasce no idioma do ator

- **WHEN** um ator com `users.locale = 'en'` conclui uma tarefa e gera o registro de
  auditoria
- **THEN** a `msg` congelada está em en

#### Scenario: Linha de auditoria não pode ser reescrita para outro idioma

- **WHEN** um UPDATE tenta trocar a `msg` de uma linha de auditoria para outro idioma
- **THEN** o trigger `trg_audit_logs_immutable` levanta exceção (append-only, inv. 3)

### Requirement: Protocolo de Comissionamento é gerado no locale do leitor

O sistema SHALL resolver os rótulos `report.v1.*` do Protocolo no **locale do LEITOR**
no momento da geração, mantendo o **versionamento de contrato** (uma string `report.v1.*`
publicada não é sobrescrita; mudança material cria versão nova).

#### Scenario: Leitor en gera o Protocolo em inglês

- **WHEN** um leitor com locale en emite o Protocolo de Comissionamento
- **THEN** os rótulos fixos do documento (título, carimbo, colunas, assinaturas) saem
  em en

#### Scenario: Mudar a grafia de uma string v1 publicada não a sobrescreve

- **WHEN** o texto de uma chave `report.v1.*` já publicada precisa mudar
- **THEN** uma chave de versão nova é criada e convive com a antiga (o sweep 8.2
  reprova sobrescrever a publicada)

### Requirement: Backend resolve o locale por requisição sem quebrar em EN

O sistema SHALL resolver o locale de cada requisição a partir da preferência da conta
(quando autenticado) e, subsidiariamente, de `Accept-Language`, aplicando-o via
`I18n.with_locale`, e SHALL fornecer o conjunto completo de arquivos `en.*.yml`
espelhando os `pt-BR.*.yml` para que nenhum caminho sob `:en` levante
`missing_translation`.

#### Scenario: Requisição de conta en resolve textos em en

- **WHEN** uma requisição autenticada de um usuário `en` renderiza uma mensagem
  server-side
- **THEN** o texto sai em en, sem `missing_translation`

#### Scenario: Toda chave pt-BR tem contraparte en

- **WHEN** o CI compara as chaves de `config/locales/pt-BR.*.yml` com `en.*.yml`
- **THEN** não há chave presente em pt-BR e ausente em en (paridade de chaves)

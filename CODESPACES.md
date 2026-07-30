# Desenvolver o RoboTrack pelo navegador (GitHub Codespaces)

Este guia é para **usar o RoboTrack sem depender do Mac** — de qualquer
computador, só com o navegador. O GitHub Codespaces monta o ambiente completo de
desenvolvimento (Ruby, Node, Postgres com os dois papéis, Redis) e já vem com o
**Claude Code** instalado. Você não precisa instalar nada na sua máquina.

> Não é a versão de produção (Render). É um ambiente de **desenvolvimento**
> descartável, só seu, para editar/testar/rodar o Claude Code.

---

## 1. Criar o Codespace (uma vez)

1. Abra o repositório no GitHub.
2. Botão verde **`Code`** → aba **`Codespaces`** → **`Create codespace on main`**.
3. Espere montar (**~3 a 8 min na primeira vez** — ele compila o Ruby, instala as
   dependências, cria o banco e o Claude Code). Nas próximas vezes é rápido.

Enquanto monta, aparece um terminal com o progresso. Quando terminar, você verá:

```
✅ Ambiente pronto.
   Para subir o app:  bash .devcontainer/scripts/dev.sh
```

### O que acontece sozinho (você não faz nada)

- Ruby 3.2.3, Node LTS e npm instalados.
- **Postgres** no ar, com os **dois papéis** de segurança do projeto
  (`robotrack_migrator` = dono/migrações; `robotrack_app` = runtime, sem
  superusuário e sob RLS) e os bancos `robotrack_dev`/`robotrack_test` migrados.
- **Redis** no ar.
- Variáveis de desenvolvimento já configuradas (nenhum segredo de produção).
- **Claude Code CLI** instalado.
- Um usuário de demonstração (`dev@robotrack.local`).

---

## 2. Rodar o app e ver no navegador

No terminal do Codespace:

```bash
bash .devcontainer/scripts/dev.sh
```

Isso sobe o **backend (Rails, porta 3000)** e o **frontend (Vite, porta 5173)**
juntos. Aguarde aparecer a linha do Vite (`Local: ...`).

Para abrir:

- O VS Code do Codespace mostra um aviso **"Open in Browser"** quando a porta
  5173 sobe — clique nele; **ou**
- Vá na aba **`Ports`** (rodapé), ache a linha **5173 — frontend**, e clique no
  ícone de globo 🌐.

A porta certa para **abrir o app é a 5173**. A 3000 é a API por trás; você não
precisa abri-la à mão.

Para **parar o app**: clique no terminal e aperte **`Ctrl + C`**.

> As portas ficam **privadas** por padrão (só você, já logado no GitHub, acessa) —
> não fica exposto na internet.

---

## 3. Usar o Claude Code lá dentro

No terminal do Codespace:

```bash
claude
```

- Na **primeira vez** ele pede **login** — é **interativo e feito só 1x** por
  Codespace (abre um link/código para você autenticar). Depois disso, é só usar.
- Se por algum motivo o comando não existir, instale com:
  `npm install -g @anthropic-ai/claude-code`

Dica: dá para ter dois terminais — um rodando o app (`dev.sh`) e outro com o
`claude`. Use o **`+`** no painel de terminal do VS Code para abrir outro.

---

## 4. Parar e apagar — para não gastar as horas grátis ⚠️

O Codespaces tem **cota de horas grátis por mês**. Um Codespace **ligado** e até
**parado (mas não apagado)** consomem cota (horas de execução / armazenamento).
Então:

- **Terminou por agora?** Feche a aba e **pare** o Codespace:
  no GitHub → **`Code`** → **`Codespaces`** → nos `...` do seu Codespace →
  **`Stop codespace`**. (Ele também para sozinho após um tempo ocioso.)
  Parar preserva seu trabalho; retomar é rápido.
- **Não vai mais usar?** **Apague**: mesma lista → `...` → **`Delete`**.
  Apagar zera o consumo de armazenamento. (Faça `commit`/`push` do que quiser
  guardar antes de apagar — o disco do Codespace some junto.)

Veja seus Codespaces e o consumo em **github.com/codespaces**.

---

## Perguntas rápidas

**Precisa do Mac ou de instalar algo?** Não. Só o navegador.

**Mexe na produção (Render)?** Não. O Codespaces é um ambiente isolado de dev;
o deploy de produção continua saindo do `push` na `main` como sempre.

**O login do Claude vale para sempre?** Vale enquanto o Codespace existir. Se você
**apagar** e criar outro, faz o login de novo (1x).

**Deu erro ao montar?** Reabra o Codespace ou crie um novo. Se persistir, mande o
texto do erro do terminal para quem cuida do projeto.

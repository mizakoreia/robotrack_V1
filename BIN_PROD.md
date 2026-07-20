# Guia do Script `bin/prod`

O script `bin/prod` foi criado para facilitar a execução do projeto em **modo de produção**, seja para testes locais (simulando o ambiente final) ou para execução simples em servidores.

## 🚀 Como Usar

1. **Prepare o Banco de Dados (apenas na primeira vez)**
   Certifique-se de ter o banco de dados de produção configurado ou crie-o localmente:

   ```bash
   RAILS_ENV=production bin/rails db:prepare
   ```

2. **Execute o Script**
   Na raiz do projeto, rode:

   ```bash
   bin/prod
   ```

3. **Acesse a Aplicação**
   - **Frontend**: http://localhost:5173
   - **Backend API**: http://localhost:3000

## 🛠 O que o script faz?

O `bin/prod` automatiza todo o fluxo necessário para rodar o app otimizado:

1.  **Checagem de Dependências**: Verifica se `ruby`, `node`, `bundler` e `npx` estão instalados.
2.  **Build do Frontend**:
    - Roda `pnpm build` (ou npm) para gerar a pasta `dist/` com os arquivos estáticos otimizados.
    - _Nota_: Se você quiser pular essa etapa (ex: já fez build antes), use `SKIP_BUILD=1 bin/prod`.
3.  **Precompilação de Assets (Backend)**:
    - Garante que assets necessários para o Rails (se houver) estejam prontos.
4.  **Execução dos Serviços**:
    - **Backend**: Inicia o servidor Puma em modo `production`.
    - **Sidekiq**: Inicia o processamento de jobs também em `production`.
    - **Frontend**: Usa o servidor estático `serve` (via npx) para servir a pasta `dist` como uma Single Page Application (SPA).

## ⚙️ Variáveis de Ambiente

Você pode customizar a execução com algumas variáveis:

| Variável     | Padrão | Descrição                                                                     |
| :----------- | :----- | :---------------------------------------------------------------------------- |
| `RAILS_PORT` | `3000` | Porta onde a API rodará.                                                      |
| `VITE_PORT`  | `5173` | Porta onde o Frontend será servido.                                           |
| `SKIP_BUILD` | `0`    | Defina como `1` para pular o build do frontend e assets (inicia mais rápido). |

## ⚠️ Diferenças para `bin/dev`

- **Otimização**: O código rodando é minificado e otimizado, não suporta Hot Module Replacement (HMR).
- **Servidor**: O frontend não é servido pelo Vite Dev Server, mas sim como arquivos estáticos reais.
- **Erros**: Você verá páginas de erro reais do usuário, não telas de debug.

## 🌐 Configuração de Servidor (Nginx + SSL)

Embora o `bin/prod` rode a aplicação localmente em HTTP, para **produção real** (acessível na internet) é **obrigatório** usar HTTPS, principalmente porque a documentação da API e recursos modernos exigem conexão segura.

A arquitetura recomendada é usar o **Nginx** como "Proxy Reverso". Ele recebe a conexão segura (HTTPS) do usuário e repassa internamente para o `bin/prod` (que roda em HTTP localmente).

### 1. Instalação (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install nginx certbot python3-certbot-nginx
```

### 2. Configuração do Nginx

Crie um arquivo de configuração para seu site: `/etc/nginx/sites-available/meuapp` (substitua `meu-dominio` pelo seu):

```nginx
server {
    server_name meu-dominio.com api.meu-dominio.com;

    # Frontend (React)
    location / {
        proxy_pass http://localhost:5173; # Porta do Frontend no bin/prod
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Backend (API + Swagger + ActionCable)
    # Redireciona requests de API e Websockets
    location ~ ^/(api|auth|cable|docs|swagger) {
        proxy_pass http://localhost:3000; # Porta do Backend no bin/prod
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade"; # Essencial para ActionCable
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Ative o site:

```bash
sudo ln -s /etc/nginx/sites-available/meuapp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 3. Configurando HTTPS (SSL Gratuito)

Com o Nginx rodando, use o Certbot para gerar os certificados automaticamente com Let's Encrypt:

```bash
sudo certbot --nginx -d meu-dominio.com -d api.meu-dominio.com
```

Siga as instruções na tela. O Certbot irá ajustar o arquivo do Nginx automaticamente para forçar HTTPS e renovação automática.

### 4. Ajuste Final no `bin/prod` (Servidor)

No servidor, crie um arquivo `.env` para garantir que o frontend saiba que está rodando em HTTPS:

```bash
# .env no servidor
VITE_API_URL=https://meu-dominio.com # URL acessível externamente
FORCE_SSL=true # Opcional, pois o Nginx já força HTTPS, mas boa prática manter
```

Rode o `bin/prod`. O Nginx vai cuidar da segurança 🔒 e o `bin/prod` cuida da aplicação 🚀.

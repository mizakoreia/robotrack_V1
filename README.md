# Rails 8 API + React TypeScript

Sistema completo com backend Rails 8 API e frontend React TypeScript, incluindo integrações com Asaas (pagamentos) e Evolution API (WhatsApp).

## 🚀 Tecnologias

### Backend (Rails 8 API)
- Rails 8 (API-only)
- Grape para APIs RESTful
- Swagger/OpenAPI documentation
- PostgreSQL
- Redis
- Sidekiq para background jobs
- Action Cable para WebSocket
- JWT authentication
- Rack Attack para rate limiting

### Frontend (React + TypeScript)
- React 18 com TypeScript
- Vite para build e dev server
- React Router para navegação
- React Query para gerenciamento de estado do servidor
- Zustand para estado global
- Tailwind CSS para estilização
- Action Cable para WebSocket
- Lucide React para ícones

## 📋 Pré-requisitos

- Ruby 3.2.0+
- Node.js 20+
- PostgreSQL 14+
- Redis 6+
- Docker (opcional)

## 🔧 Instalação

### Opção 1: Setup Automatizado
```bash
# Clone o repositório
git clone <url-do-repositorio>
cd robotrack

# Execute o script de setup
chmod +x setup.sh
./setup.sh
```

### Opção 2: Setup Manual

#### Backend
```bash
cd backend
bundle install
rails db:create db:migrate
rails server
```

#### Frontend
```bash
cd frontend
npm install
npm run dev
```

### Opção 3: Docker
```bash
# Desenvolvimento
docker-compose up

# Produção
docker-compose -f docker-compose.prod.yml up
```

## 📚 Documentação

- [Documentação de Setup](BUILD_SYSTEM.md)
- [Regras do Projeto](.trae/rules/project_rules.md)
- API Documentation: `http://localhost:3000/swagger_doc`
- Stoplight Elements: `http://localhost:3000/docs`

### 🔐 Autenticação JWT e Client Application

- Tipos de token:
  - Token de Usuário (JWT): emitido após login (Magic Login, OAuth). Assinado com `HS256` e expira em 15 minutos. Possui refresh token válido por 7 dias.
  - Token de Client Application (vitalício): string estática cadastrada via seeds e usada por integrações e fluxos sem usuário autenticado (ex.: envio de mensagem de WhatsApp na página de login).

- Headers:
  - `Authorization: Bearer <token>`

- Uso:
  - Endpoints exigem token válido (JWT de usuário OU token de Client Application), exceto webhooks do WhatsApp e documentação Swagger.
- O endpoint `POST /whats/v1/messages/send_message` exige token de Client Application.

- Renovação:
  - `POST /api/auth/v1/sessions/refresh` com `refresh_token` retorna novo par de tokens.

- Erros comuns:
  - 401 `unauthorized`: token ausente, inválido ou expirado
  - 403 `forbidden`: acesso negado
  - 429 `rate_limit_exceeded`: muitas tentativas

### 🔑 Client Application

- Modelo: `ClientApplication(name, token, active)`
- Seeds criam apps padrão (`ASAAS`, `FRONTEND_PUBLIC`) com tokens gerados e ativos.
- Tokens são vitalícios (não expiram) e devem ser mantidos em segredo.

### 🔓 Fluxo de Magic Login

- `POST /api/v1/auth/pre-register` solicita código (email/WhatsApp) mesmo sem conta existente.
- `POST /api/v1/auth/verify-code` valida código (checa expiração e correspondência).
- `POST /api/v1/auth/complete-registration` conclui cadastro (nome + campo complementar) e emite tokens JWT.
  - Regras de validação: nome mínimo 3 caracteres; email padrão; WhatsApp em formato internacional (10–15 dígitos, sem `+`).
  - Segurança: rate limit, bloqueio de brute force, expiração em 5 min, tentativas máximas.
- Segurança: rate limit, bloqueio de brute force, expiração e tentativas máximas.

## 🧪 Testes

### Backend
```bash
cd backend
bundle exec rspec
```

### Frontend
```bash
cd frontend
npm test
```

## 🚀 Deploy

### CI/CD
O projeto inclui GitHub Actions para:
- Testes automatizados
- Linting e análise de segurança
- Build e deploy

### Produção
```bash
# Backend
cd backend
RAILS_ENV=production bundle exec rails server

# Frontend
cd frontend
npm run build
npm run preview
```

## 🔐 Variáveis de Ambiente

Copie os arquivos de exemplo:
```bash
cp backend/.env.example backend/.env
cp frontend/.env.example frontend/.env
cp .env.example .env
```

## 📖 Uso

1. Acesse `http://localhost:5173`
2. Faça login com as credenciais demo
3. Explore as funcionalidades de pagamentos e WhatsApp

## 🤝 Contribuindo

1. Faça fork do projeto
2. Crie sua feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📝 Licença

Este projeto está sob a licença MIT.

## 📞 Suporte

Para suporte, abra uma issue no repositório.
# 🚀 Build System - Rails 8 API + React TypeScript

Estrutura de build completa para novos apps seguindo as regras do projeto Rails 8 API + React TypeScript.

## 📁 Estrutura do Projeto

```
.
├── backend/                 # Rails 8 API-only
│   ├── app/
│   │   ├── controllers/api/v1/  # Endpoints Grape
│   │   ├── channels/           # Action Cable
│   │   ├── models/              # ActiveRecord
│   │   ├── services/            # Serviços de negócio
│   │   └── jobs/                # ActiveJob/Sidekiq
│   ├── config/
│   ├── spec/                    # RSpec tests
│   └── Gemfile
├── frontend/                # React + TypeScript
│   ├── src/
│   │   ├── app/                # Páginas/rotas
│   │   ├── components/         # Componentes React
│   │   ├── features/           # Features por domínio
│   │   ├── lib/api/            # Cliente HTTP
│   │   └── store/              # Estado (Zustand)
│   └── package.json
├── .github/workflows/       # CI/CD
├── docker-compose.yml       # Desenvolvimento local
└── Dockerfile              # Build multi-stage
```

## 🚀 Início Rápido

### Pré-requisitos

- Ruby 3.2.0+
- Node.js 20+
- PostgreSQL 14+
- Redis 7+
- Docker (opcional)

### Setup Local

1. **Clone o repositório**
   ```bash
   git clone <seu-repo>
   cd <seu-projeto>
   ```

2. **Configure as variáveis de ambiente**
   ```bash
   # Backend
   cp backend/.env.example backend/.env
   
   # Frontend
   cp frontend/.env.example frontend/.env
   
   # Docker (opcional)
   cp .env.example .env
   ```

3. **Setup com Script (Automático)**
   ```bash
   # Torna scripts executáveis e normaliza finais de linha
   chmod +x setup.sh create_dev_db.sh
   
   # Roda o setup completo (provisiona banco, instala deps, prepara projetos)
   ./setup.sh
   ```

   Flags úteis (variáveis de ambiente):
   - `USE_SUDO=true|false` para controlar uso de sudo no `create_dev_db.sh`.
   - `CONFIG_PATH=/caminho/para/database.yml` para apontar um arquivo específico.

4. **Setup com Docker (Recomendado)**
   ```bash
   docker-compose up -d
   ```

5. **Setup Manual**
   
   **Backend:**
   ```bash
   cd backend
   bundle install
   # Provisiona banco opcionalmente
   ../create_dev_db.sh
   
   # Prepara banco (cria, migra e seed se configurado)
   rails db:prepare
   rails server
   ```
   
   **Frontend:**
   ```bash
   cd frontend
   npm install
   npm run dev
   ```

## 🔧 Scripts de Build

### Backend

```bash
# Desenvolvimento
cd backend
bundle exec rails server

# Testes
bundle exec rspec
bundle exec rubocop
bundle exec brakeman
bundle exec bundle-audit check

# Produção
RAILS_ENV=production bundle exec rails server
```

### Frontend

```bash
# Desenvolvimento
cd frontend
npm run dev

# Build
npm run build

# Testes
npm run test
npm run test:coverage
npm run lint
npm run type-check

# Preview produção
npm run preview
```

## 🐳 Docker

### Desenvolvimento

```bash
# Iniciar todos os serviços
docker-compose up -d

# Ver logs
docker-compose logs -f

# Parar
docker-compose down
```

### Produção

```bash
# Build imagens
docker build --target backend-prod -t app-backend .
docker build --target frontend-nginx -t app-frontend .

# Rodar
docker run -p 3000:3000 app-backend
docker run -p 80:80 app-frontend
```

## 📊 CI/CD

O pipeline GitHub Actions executa:

### Backend
- ✅ RuboCop (lint)
- ✅ Brakeman (segurança)
- ✅ Bundle Audit (vulnerabilidades)
- ✅ RSpec (testes)
- ✅ Cobertura 90%+

### Frontend
- ✅ ESLint (lint)
- ✅ TypeScript check
- ✅ Testes com Vitest
- ✅ Build de produção
- ✅ Bundle size check

### Segurança
- ✅ Trivy vulnerability scanner
- ✅ Dependabot alerts

## 🌍 Variáveis de Ambiente

### Backend (.env)
```env
DATABASE_URL=postgres://user:pass@localhost:5432/app_development
REDIS_URL=redis://localhost:6379/1
SECRET_KEY_BASE=your-secret-key
ASAAS_API_KEY=your-asaas-key
EVOLUTION_API_KEY=your-evolution-key
```

### Frontend (.env)
```env
VITE_API_URL=http://localhost:3000
VITE_WS_URL=ws://localhost:3000/cable
VITE_DEFAULT_THEME=light
```

## 🔌 Integrações

### APIs Configuradas

- **Asaas (Pagamentos)**: Webhooks, cobranças, QR Code PIX
- **Evolution (WhatsApp)**: Envio/recepção de mensagens, webhooks
- **Action Cable**: Real-time para notificações e estados

### Exemplos de Uso

```bash
# Criar novo endpoint API
rails generate grape:api v1/payments

# Criar novo componente React
npm run generate:component PaymentForm

# Rodar testes específicos
bundle exec rspec spec/requests/api/v1/payments_spec.rb
npm run test -- --grep "PaymentComponent"
```

## 📚 Documentação

- **API Swagger**: `http://localhost:3000/swagger_doc`
- **Stoplight Elements**: `http://localhost:5173/docs`
- **Storybook**: `http://localhost:6006` (opcional)

## 🚨 Troubleshooting

### Problemas Comuns

1. **PostgreSQL connection refused**
   ```bash
   # Verificar se PostgreSQL está rodando
   sudo service postgresql start
   
   # Criar usuário
   sudo -u postgres createuser -s seu-usuario
   ```

2. **Redis connection refused**
   ```bash
   # Iniciar Redis
   redis-server
   ```

3. **Porta já em uso**
   ```bash
   # Backend
   lsof -ti:3000 | xargs kill -9
   
   # Frontend
   lsof -ti:5173 | xargs kill -9
   ```

## 🎯 Próximos Passos

1. Configure suas integrações (Asaas, Evolution)
2. Personalize temas e componentes
3. Configure deploy (Vercel, Heroku, AWS)
4. Configure monitoramento (Sentry, New Relic)
5. Configure backup do banco

## 📞 Suporte

Para problemas ou dúvidas:

1. Verifique os logs: `docker-compose logs -f`
2. Execute testes: `npm run test` / `bundle exec rspec`
3. Verifique variáveis de ambiente
4. Consulte a documentação em `.trae/rules/project_rules.md`

---

**facinho, né ruyter?** 🚀
# Base image for backend
FROM ruby:3.2.0-alpine AS backend-base

RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    postgresql-client \
    tzdata \
    nodejs \
    npm \
    git

WORKDIR /app

# Copy Gemfile and install dependencies
COPY backend/Gemfile backend/Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Development stage
FROM backend-base AS backend-dev

RUN apk add --no-cache \
    bash \
    curl

COPY backend/ .

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

# Production stage
FROM backend-base AS backend-prod

# delivery-and-observability 2.1: app é API-only (sem pipeline de assets), roda
# como usuário NÃO-root e expõe um HEALTHCHECK de liveness. `curl` para a sonda.
RUN apk add --no-cache curl && \
    addgroup -S app && adduser -S app -G app

COPY backend/ .
RUN chown -R app:app /app
USER app

EXPOSE 3000

# Liveness: o processo responde? (NÃO checa Postgres/Redis — isso é /health/ready,
# do orquestrador, não do restart de container.)
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:3000/health/live || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

# Frontend base image
FROM node:20-alpine AS frontend-base

WORKDIR /app

# Copy package files
COPY frontend/package*.json ./
RUN npm ci --only=production

# Development stage
FROM frontend-base AS frontend-dev

RUN npm ci

COPY frontend/ .

EXPOSE 5173

CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# Production stage
FROM frontend-base AS frontend-prod

COPY frontend/ .

RUN npm run build

# Serve with nginx
FROM nginx:alpine AS frontend-nginx

COPY --from=frontend-prod /app/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
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

COPY backend/ .

RUN RAILS_ENV=production bundle exec rails assets:precompile

EXPOSE 3000

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
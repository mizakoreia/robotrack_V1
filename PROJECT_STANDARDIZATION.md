# Padronização de Rotas da API

Este documento registra a decisão de padronização dos endpoints da API e os ajustes realizados.

## Decisão

- Padrão oficial: versionamento por módulo Grape:
  - Autenticação: `http://<host>/auth/v1/...`
  - WhatsApp: `http://<host>/whats/v1/...`
  - Asaas: `http://<host>/asaas/v1/...`
- O roteamento é exclusivamente gerenciado pelo Grape; não utilizamos redirects no `routes.rb`.
- Documentação Swagger é servida em `GET /swagger_doc` e visualizada em `GET /docs` (Stoplight Elements).

## Ajustes Implementados

- Atualizado Stoplight Elements para consumir `apiDescriptionUrl="/swagger_doc"`.
- Mantido apenas o mount do `Api::Root` e a rota `/docs`.
- Atualizado `README.md` com os links:
  - API Docs: `http://localhost:3000/swagger_doc`
  - Visualização: `http://localhost:3000/docs`

## Impacto em Documentação

- Documentos internos devem usar `/auth/v1/...`, `/whats/v1/...`, `/asaas/v1/...`.
- Exemplos curl devem sempre incluir o prefixo `/api/v1`.

## Testes

- Adicionado teste de request mínimo (`spec/requests/swagger_spec.rb`) validando:
  - `/swagger_doc` retorna 200 e `application/json`.
  - Formatos legados `/api/v1/*` não são suportados.

## Comunicação

- Time deve adotar somente `/api/v1/*` em novas features e correções.
- Qualquer divergência deve ser tratada diretamente nos módulos Grape, sem criar entries em `routes.rb`.
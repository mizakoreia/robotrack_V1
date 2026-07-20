---
trigger: always_on
---

# Integrations (Evolution API & Asaas)

## 8) Integrações — Notas Operacionais

### 8.1 Evolution API (WhatsApp)

* Requisitos de autenticação, limites e formato de mensagens centralizados em `services/evolution/*`.
* Webhook único mapeando eventos → comandos de domínio; sempre logar request_id e signature.
* Rejeitar/ignorar duplicados via chave idempotente (message id).

### 8.2 Asaas (Pagamentos)

* **Clientes → Cobranças → Webhooks**.
* Estados: `pending`, `paid`, `refunded`, `failed`, `expired`.
* QR Code PIX obtido e cacheado; broadcasts de mudança de estado.

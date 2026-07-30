# internationalization

App em **inglês além do português**, com **seletor PT/EN por bandeira** (BR/GB,
não-emoji, acessível). Change de **planejamento (G0)**: materializa o mapa, os grupos
e — o mais importante — o **`GLOSSARIO.md`** (pt-BR → EN proposto, com as linhas de
robótica/comissionamento marcadas ⚠️ para o dono confirmar). **Nada foi traduzido nem
aplicado.**

Decisão-chave (mensagens congeladas do backend): **congela-para-frente, não
reescreve-para-trás** — notificação no locale do destinatário, auditoria no locale do
ator, relatório no locale do leitor; históricos permanecem no idioma de origem. Única
migração de banco: `users.locale` (🟡 aditiva). Sem ponto 🔴.

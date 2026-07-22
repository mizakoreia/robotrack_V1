// Módulo ÚNICO dos textos do modal de auditoria (audit-log 6.3, D14). O TEXTO do
// registro (`msg`) e o horário (`ts_local`) NÃO estão aqui — vêm renderizados do
// servidor (Decisão 4/5). Aqui só o chrome do modal (título, estados).
export const auditText = {
  title: 'Log de auditoria',
  subtitle: 'Registros mais recentes (até 200). Trilha imutável.',
  loading: 'Carregando o log…',
  loadError: 'Não foi possível carregar o log de auditoria.',
  empty: 'Nenhum registro de auditoria ainda.',
  close: 'Fechar',
}

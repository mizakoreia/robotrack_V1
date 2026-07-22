// Módulo ÚNICO dos textos da tela de Configurações (workspace-settings, D14). Aqui
// só o chrome da tela; nomes de pessoa e horários NUNCA são literais.
export const settingsText = {
  title: 'Configurações',
  // Painel de Equipe (§3.9)
  teamTitle: 'Equipe',
  teamSubtitle: 'Responsáveis do workspace. Remover arquiva a pessoa e preserva o histórico.',
  teamEmpty: 'Nenhuma pessoa cadastrada ainda.',
  teamAddPlaceholder: 'Nome da pessoa',
  teamAdd: 'Adicionar',
  teamRemoveAria: (name: string) => `Remover ${name}`,
  teamMember: 'membro',
  errorNameTaken: 'Já existe uma pessoa com esse nome.',
  errorNameBlank: 'Informe um nome.',
  errorHasMembership: 'Essa pessoa é membro do workspace — remova-a pela tela de Equipe/Membros.',
  errorGeneric: 'Não foi possível concluir. Tente novamente.',
}

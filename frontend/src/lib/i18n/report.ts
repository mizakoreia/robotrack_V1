// Módulo ÚNICO dos textos da TELA do relatório (commissioning-report 8.3, D14).
// Atenção à fronteira (D-R9): o texto DO DOCUMENTO (títulos de seção, colunas,
// rodapé, assinaturas…) vem resolvido do servidor no payload — aqui só o chrome
// da tela (seletor, estados) que NÃO sai no papel.
export const reportText = {
  title: 'Relatório',
  scopeLabel: 'Escopo do documento',
  scopeAll: 'Workspace inteiro',
  print: 'Imprimir',

  loading: 'Montando o documento…',

  // §4.3 — sem conexão a tela INFORMA; nunca monta o documento de cache parcial.
  offlineTitle: 'Sem conexão',
  offlineBody:
    'A emissão do Protocolo exige conexão com o servidor — o documento não é montado a partir de dados locais.',

  errorTitle: 'Não foi possível emitir o documento',
  errorBody: 'O servidor falhou durante a montagem. Nenhuma seção parcial foi exibida.',
  retry: 'Tentar novamente',
}

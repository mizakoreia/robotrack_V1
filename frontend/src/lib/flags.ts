// Feature flags do cliente (espelham as do servidor — a VERDADE é o servidor:
// flag desligada lá responde 404 mesmo que a UI mostre o botão). Módulo próprio
// para os testes poderem mockar sem tocar em import.meta.env.
export const flags = {
  // workspace-settings 5.8 — com a flag desligada o botão de reset SOME (e o
  // endpoint devolve 404 de qualquer forma).
  factoryReset: import.meta.env.VITE_FEATURE_FACTORY_RESET === 'true',
}

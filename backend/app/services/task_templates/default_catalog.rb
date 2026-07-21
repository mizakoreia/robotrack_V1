# frozen_string_literal: true

module TaskTemplates
  # task-catalog 3.1 (§1.3, D-TC-4) — o catálogo padrão de 31 tarefas-base, em 9
  # categorias, semeado em TODO workspace novo (`SeedDefaultTaskTemplatesService`).
  #
  # É DADO transcrito do legado (`workspace.defaultTasks`), não código copiado: o
  # array é escrito do zero aqui, mas cada `desc` reproduz a grafia do original —
  # inclusive os erros (`"Traj, de Descarte"`, `"Otimização de Trajetoria"`,
  # `"Dryrun Baixa velocidade ate 100%"`, `"Automatico baixa velocidade"`, `"Robo"`
  # sem acento). Motivo: a importação do legado (`legacy-data-migration`, §1.4
  # item 3) casa por `desc`; "corrigir" a ortografia aqui faria o mesmo item
  # aparecer duas vezes na migração — uma do catálogo semeado, outra do dump.
  #
  # O prefixo de ordenação (`A. `, `B. `…) vive DENTRO de `cat` (D-TC-1): é o
  # critério de ordenação lexicográfica, sem coluna de ordem separada.
  #
  # `weight` é `1` em todos (D-TC-4). `app_filters` é `[]` (vale para todo robô)
  # exceto nos DOIS itens da §1.3 com filtro real — e só eles.
  module DefaultCatalog
    DEFAULT_WEIGHT = 1

    # Cada linha: [cat, desc] ou [cat, desc, app_filters]. Ordem = ordem de
    # semeadura e de exibição (A. Hardware … I. Aceitação).
    ITEMS = [
      ['A. Hardware',    'Power On'],
      ['A. Hardware',    'Mastering Check'],
      ['A. Hardware',    'Montagem de Ferramenta'],
      ['A. Hardware',    'Check de Ferramenta/Umbilical'],

      ['B. Rede',        'Config. Endereço de IP'],
      ['B. Rede',        'Rede Principal'],
      ['B. Rede',        'Sub Rede'],

      ['C. Segurança',   'Definir Cubos e esferas de segurança'],
      ['C. Segurança',   'Self Check de segurança do Robo'],

      ['D. Processo',    'TCP Check'],
      ['D. Processo',    'Calibração de Frame'],
      ['D. Processo',    'Payload'],
      ['D. Processo',    'Calibração de Cola',        ['Sealing']],
      ['D. Processo',    'Check sinais de Gripper',   ['Handling', 'Solda Ponto']],

      ['E. Trajetórias', 'Carregar OLP'],
      ['E. Trajetórias', 'Teach Traj. Sem Peça'],
      ['E. Trajetórias', 'Teach Traj. Com Peça'],
      ['E. Trajetórias', 'Carregar Parâmetros'],
      ['E. Trajetórias', 'Traj, de Descarte'],
      ['E. Trajetórias', 'Manutenção'],

      ['F. Interlocks',  'PLC-ROB interlocks/Sinais'],

      ['G. Tryout',      'Dryrun Baixa velocidade ate 100%'],
      ['G. Tryout',      'Dryrun Diferentes velocidades'],
      ['G. Tryout',      'Automatico baixa velocidade'],
      ['G. Tryout',      'Speed up'],

      ['H. Otimização',  'Medição de Tempo de Ciclo Com peça'],
      ['H. Otimização',  'Otimização de Trajetoria'],

      ['I. Aceitação',   'Check de aceitação interna'],
      ['I. Aceitação',   'Check de aceitação do cliente'],
      ['I. Aceitação',   'Treinamento ao cliente'],
      ['I. Aceitação',   'Acompanhamento']
    ].map { |cat, desc, filtros| { cat: cat, desc: desc, app_filters: filtros || [] } }.freeze

    # Linhas prontas para `insert_all` num workspace. `workspace_id` explícito em
    # cada hash (Armadilha 3): `insert_all` pula callbacks E `default_scope`, então
    # sem isso a RLS rejeitaria o INSERT (WITH CHECK exige workspace_id do contexto).
    # `id`, `created_at` e `updated_at` ficam a cargo dos DEFAULTs do banco.
    def self.rows_for(workspace_id)
      ITEMS.map do |item|
        {
          workspace_id: workspace_id,
          cat: item[:cat],
          desc: item[:desc],
          weight: DEFAULT_WEIGHT,
          app_filters: item[:app_filters]
        }
      end
    end
  end
end

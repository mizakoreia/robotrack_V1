# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 2.6 (§D5.b) — o sweep que mantém o cache honesto. A ATUALIDADE
# do `progress_cache` não é garantida por constraint (só o domínio 0..100 é);
# é garantida por (a) ponto de escrita único, (b) ESTE sweep, (c) o job de
# reconciliação. Se algum arquivo novo escrever `progress_cache` fora de
# `app/services/progress/`, ou mexer em `tasks.progress/status/weight` por baixo
# do pano fora dos writers abençoados, ou abrir `without_cascade` sem fechar com
# `BulkRecompute`, o CI reprova nomeando arquivo e linha.
RSpec.describe 'Fronteira de escrita do progresso (D5.b)', type: :model do
  PWB_APP = Rails.root.join('app')

  def self.rb_files
    Dir[PWB_APP.join('**/*.rb')]
  end

  # Escritas de `progress_cache`: atribuição, chave de hash de update, ou SQL SET.
  # Leituras (`record.progress_cache`, `x.progress_cache)`) não casam.
  PWB_CACHE_WRITE = /progress_cache\s*(=[^=]|:)|SET\s+progress_cache/i
  # Só `app/services/progress/` pode escrever o cache.
  PWB_PROGRESS_DIR = %r{/app/services/progress/}

  it 'nenhum arquivo fora de app/services/progress/ escreve progress_cache' do
    ofensores = []
    self.class.rb_files.each do |file|
      next if file.match?(PWB_PROGRESS_DIR)

      File.readlines(file).each_with_index do |linha, i|
        next if linha.strip.start_with?('#')

        ofensores << "#{file.sub(PWB_APP.to_s, 'app')}:#{i + 1}" if linha.match?(PWB_CACHE_WRITE)
      end
    end
    expect(ofensores).to be_empty,
                         "progress_cache escrito fora de app/services/progress/ (D5.b):\n#{ofensores.join("\n")}"
  end

  # `tasks.progress/status/weight` só podem ser mutados por baixo do pano
  # (`update_column(s)`, `update_all`, SQL SET) nos writers abençoados. Um
  # importador novo com `update_column(:progress, …)` cai aqui.
  PWB_BLESSED = %r{/app/services/(tasks|task_advances|robots|progress)/}
  PWB_RAW_TASK_WRITE = /update_columns?\(\s*:?(progress|status|weight)\b|update_all\(.*\b(progress|status|weight)\s*:|SET\s+(progress|status|weight)\b/i
  # `status` também é coluna de OUTRAS tabelas (`workspace_backups`,
  # workspace-settings): um `WorkspaceBackup...update_all(status:)` NÃO é escrita
  # em tarefa. O sweep é textual e não vê a tabela receptora, então isenta os
  # receptores não-tarefa conhecidos, pelo nome do model/tabela na MESMA linha.
  # (hierarchy-soft-delete — reconciliação cross-change; falso positivo latente
  # desde workspace-settings G4.)
  PWB_NON_TASK_STATUS_WRITER = /\b(WorkspaceBackup|workspace_backups)\b/

  it 'tasks.progress/status/weight só são mutados via os services abençoados' do
    ofensores = []
    self.class.rb_files.each do |file|
      next if file.match?(PWB_BLESSED)

      File.readlines(file).each_with_index do |linha, i|
        next if linha.strip.start_with?('#')
        next if linha.match?(PWB_NON_TASK_STATUS_WRITER)

        ofensores << "#{file.sub(PWB_APP.to_s, 'app')}:#{i + 1}" if linha.match?(PWB_RAW_TASK_WRITE)
      end
    end
    expect(ofensores).to be_empty,
                         "escrita crua em tasks.progress/status/weight fora dos writers abençoados:\n#{ofensores.join("\n")}"
  end

  it 'todo arquivo que usa without_cascade também chama BulkRecompute' do
    definidor = %r{/app/services/progress\.rb\z} # o que DEFINE a flag, não a usa
    ofensores = []
    self.class.rb_files.each do |file|
      next if file.match?(definidor)

      conteudo = File.read(file)
      next unless conteudo.include?('without_cascade')

      ofensores << file.sub(PWB_APP.to_s, 'app') unless conteudo.include?('BulkRecompute')
    end
    expect(ofensores).to be_empty,
                         "without_cascade sem BulkRecompute no mesmo arquivo (D5.c):\n#{ofensores.join("\n")}"
  end
end

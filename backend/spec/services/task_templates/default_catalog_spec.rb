# frozen_string_literal: true

require 'rails_helper'

# task-catalog 3.2 (§1.3, D-TC-4) — spec de TRAVA do catálogo padrão. Adicionar,
# remover ou renomear qualquer item quebra este spec, forçando a atualização
# consciente da spec funcional (e a decisão de mexer no que a migração legada
# casa por `desc`).
RSpec.describe TaskTemplates::DefaultCatalog do
  let(:items) { described_class::ITEMS }

  it 'tem exatamente 31 itens' do
    expect(items.size).to eq(31)
  end

  it 'distribui os itens em exatamente 9 categorias distintas' do
    expect(items.map { |i| i[:cat] }.uniq.size).to eq(9)
  end

  it 'as 9 categorias são A. Hardware … I. Aceitação, na ordem de §1.3' do
    expect(items.map { |i| i[:cat] }.uniq).to eq(
      [
        'A. Hardware', 'B. Rede', 'C. Segurança', 'D. Processo', 'E. Trajetórias',
        'F. Interlocks', 'G. Tryout', 'H. Otimização', 'I. Aceitação'
      ]
    )
  end

  it 'não há descrição duplicada, nem mesmo a menos de espaços/caixa' do
    normalizadas = items.map { |i| i[:desc].strip.downcase }
    expect(normalizadas.uniq.size).to eq(31)
  end

  it 'exatamente 2 itens têm filtro de aplicação não vazio, e são os dois de §1.3' do
    com_filtro = items.reject { |i| i[:app_filters].empty? }

    expect(com_filtro.size).to eq(2)
    expect(com_filtro.find { |i| i[:desc] == 'Calibração de Cola' }[:app_filters]).to eq(['Sealing'])
    expect(com_filtro.find { |i| i[:desc] == 'Check sinais de Gripper' }[:app_filters])
      .to eq(['Handling', 'Solda Ponto'])
  end

  it 'o conjunto de descrições é exatamente o de §1.3 (grafias do legado preservadas)' do
    esperado = [
      # A. Hardware
      'Power On', 'Mastering Check', 'Montagem de Ferramenta', 'Check de Ferramenta/Umbilical',
      # B. Rede
      'Config. Endereço de IP', 'Rede Principal', 'Sub Rede',
      # C. Segurança
      'Definir Cubos e esferas de segurança', 'Self Check de segurança do Robo',
      # D. Processo
      'TCP Check', 'Calibração de Frame', 'Payload', 'Calibração de Cola', 'Check sinais de Gripper',
      # E. Trajetórias
      'Carregar OLP', 'Teach Traj. Sem Peça', 'Teach Traj. Com Peça', 'Carregar Parâmetros',
      'Traj, de Descarte', 'Manutenção',
      # F. Interlocks
      'PLC-ROB interlocks/Sinais',
      # G. Tryout
      'Dryrun Baixa velocidade ate 100%', 'Dryrun Diferentes velocidades',
      'Automatico baixa velocidade', 'Speed up',
      # H. Otimização
      'Medição de Tempo de Ciclo Com peça', 'Otimização de Trajetoria',
      # I. Aceitação
      'Check de aceitação interna', 'Check de aceitação do cliente', 'Treinamento ao cliente',
      'Acompanhamento'
    ]

    expect(items.map { |i| i[:desc] }).to eq(esperado)
  end

  it 'preserva as grafias erradas do legado (o importador casa por desc)' do
    descricoes = items.map { |i| i[:desc] }
    # Se alguém "corrigir" a ortografia, o item duplica na migração do legado.
    expect(descricoes).to include('Traj, de Descarte')          # vírgula no lugar do ponto
    expect(descricoes).to include('Otimização de Trajetoria')   # sem acento em "Trajetória"
    expect(descricoes).to include('Dryrun Baixa velocidade ate 100%') # "ate" sem acento
    expect(descricoes).to include('Automatico baixa velocidade') # "Automatico" sem acento
    expect(descricoes).not_to include('Trajetória de Descarte')
  end
end

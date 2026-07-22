# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 7.1 (§3.8) — assinaturas e rodapé. Os DOIS blocos
# (Comissionador / Cliente) vêm vazios — NENHUM preenchimento automático com o
# usuário logado. O rodapé traz o id CARIMBADO (byte a byte o mesmo dos metadados,
# não um segundo Time.current), a data de geração e a nota de rastreabilidade da
# chave de locale `report.v1.footer_traceability`.
RSpec.describe 'commissioning-report — assinaturas e rodapé', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Marina Alves') }
  let(:ws)    { make_workspace(owner: owner) }
  before { in_workspace(ws) { Person.create!(name: 'Marina Alves', user_id: owner.id) } }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)

  def seed
    in_workspace(ws) do
      p = Project.create!(name: 'Linha A', position: 0)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      create_task(r, desc: 'T', position: 0, status: 'Pendente', progress: 0)
    end
  end

  it 'exatamente um bloco Comissionador e um Cliente / Aceite, ambos SEM preenchimento' do
    seed
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    sigs = body['signatures']
    expect(sigs.size).to eq(2)
    expect(sigs.map { |s| s['key'] }).to eq(%w[commissioner client])
    expect(sigs.map { |s| s['label'] }).to eq(['Comissionador', 'Cliente / Aceite'])
    # nenhum bloco vem pré-preenchido: só key+label — sem nome, sem data
    sigs.each { |s| expect(s.keys.sort).to eq(%w[key label]) }
    expect(sigs.to_s).not_to include('Marina')
  end

  it 'rodapé: id byte a byte igual ao dos metadados, data de geração e nota de rastreabilidade' do
    seed
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    footer = body['footer']
    expect(footer['document_id']).to eq(body['document_id'])
    expect(footer['document_id']).to eq(body['metadata']['document_id'])
    expect(footer['generated_at']).to eq(body['metadata']['issued_at']) # um só instante de emissão
    expect(footer['traceability']).to eq(I18n.t('report.v1.footer_traceability'))
    expect(footer['generated_at_label']).to eq(I18n.t('report.v1.footer_generated_at'))
  end

  it 'a faixa de continuação e as linhas de assinatura viajam em labels (D-R9)' do
    seed
    get '/api/v1/commissioning_report?scope=all', headers: headers
    labels = JSON.parse(response.body)['labels']
    expect(labels['signature_name']).to eq('Nome')
    expect(labels['signature_field']).to eq('Assinatura')
    expect(labels['signature_date']).to eq('Data')
    expect(labels['history_continues']).to eq('— histórico continua na próxima página —')
  end
end

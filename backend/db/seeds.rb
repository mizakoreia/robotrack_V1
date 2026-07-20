# frozen_string_literal: true

def truthy_env(key, default)
  v = ENV[key]
  return default if v.nil?

  !!(v =~ /\A(true|1|yes|on)\z/i)
end

should_perform_users = truthy_env('SEED_USERS', true)
should_perform_client_application = truthy_env('SEED_CLIENT_APPS', true)
should_perform_instance_whats = truthy_env('SEED_WHATS_INSTANCE', true)
should_perform_leads_operations = truthy_env('SEED_LEADS', true)
should_perform_lead_messages = truthy_env('SEED_LEAD_MESSAGES', true)

leads_only = (ENV['SEED_LEADS_ONLY'] || '').split(',').map(&:strip).reject(&:empty?)
leads_skip = (ENV['SEED_LEADS_SKIP'] || '').split(',').map(&:strip).reject(&:empty?)

if should_perform_instance_whats
  if Rails.env.production?
    params = {
      instanceName: 'ROBOTRACK_WHATS',
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true
    }
  else
    raw_tag = ENV['USER'] || ENV['USERNAME'] || Socket.gethostname
    user_tag = I18n.transliterate(raw_tag).gsub(/[\s\-.]+/, '_').gsub(/[^a-zA-Z0-9_]/, '').upcase
    params = {
      instanceName: "ROBOTRACK_#{user_tag}",
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true
    }
  end

  begin
    # Tenta buscar na Evolution API
    params_result = { instance_name: params[:instanceName] }
    result_exists = EvolutionConnection.list_instances(params_result)

    puts '✅ Instância encontrada na Evolution API.'

    instance_data = result_exists[:response].first

    polemk_instance = PolemkInstance.find_or_initialize_by(instance_name: instance_data['name'])

    polemk_instance.assign_attributes(
      display_name: 'Robotrack',
      instance_name: instance_data['name'],
      instance_id: instance_data['id'],
      integration: instance_data['integration'],
      is_qrcode: params[:qrcode],
      api_key: instance_data['token'],
      raw_response: instance_data
    )
    polemk_instance.save!
    puts '✅ Instância recuperada e salva no banco!'
    puts '🔎 procurando webhooks...'
    result_webhook = EvolutionConnection.list_webhooks
    if result_webhook[:response].present?
      events = %w[SEND_MESSAGE MESSAGES_UPSERT MESSAGES_UPDATE]
      events.each do |event|
        full_url = "#{result_webhook[:response]['url']}/#{event.downcase.tr('_', '-')}"
        webhook = polemk_instance.polemk_webhooks.find_or_initialize_by(event: event)
        webhook.update(
          url: full_url,
          enabled: true,
          webhook_by_events: true,
          webhook_base_64: true,
          raw_response: result_webhook[:response]
        )
      end

      puts '✅ Webhooks da Instância criados no banco!'
    else
      puts '🔎 sem webhook configurado na instancia...'
    end
  rescue EvolutionConnection::InvalidResponseError => e
    if e.status == 404
      puts '🔎 Instância não encontrada na Evolution API, criando nova...'

      begin
        result_create = EvolutionConnection.create_instance(params)
        response = result_create[:response]
        instance_data = response['instance']

        polemk_instance = PolemkInstance.find_or_initialize_by(instance_name: instance_data['instanceName'])

        polemk_instance.assign_attributes(
          display_name: 'Robotrack',
          instance_name: instance_data['instanceName'],
          instance_id: instance_data['instanceId'],
          integration: instance_data['integration'],
          is_qrcode: params[:qrcode],
          api_key: response['hash'].is_a?(Hash) ? response['hash']['apikey'] : response['hash'],
          raw_response: response
        )
        polemk_instance.save!
        puts '✅ Instância criada e salva no banco!'
      rescue StandardError => e
        puts "🧨 Erro inesperado ao criar: #{e.class} - #{e.message}"
      end

    else
      puts "❌ Falha na comunicação com Evolution API: #{e.error} (#{e.status})"
      puts "Detalhes: #{e.details}"
    end
  rescue EvolutionConnection::TimeoutError, EvolutionConnection::ConnectionError => e
    puts "🚨 Erro de comunicação com a Evolution API: #{e.message}"
  rescue StandardError => e
    puts "🧨 Erro inesperado: #{e.class} - #{e.message}"
  end
end

if should_perform_leads_operations
  puts '📌 Criando operações para categorizar leads...'
  operations_data = [
    { key: 'SITE_INSTITUCIONAL', title: 'Site Institucional',
      description: 'Criação de site institucional completo com foco em branding', keywords: %w[institucional site empresa sobre contato] },
    { key: 'E_COMMERCE', title: 'Loja Online', description: 'E-commerce com checkout simples e integração básica',
      keywords: %w[ecommerce loja produto carrinho checkout] },
    { key: 'APP_AGENDAMENTO', title: 'Aplicativo de Agendamento',
      description: 'Aplicativo web para gestão de horários e reservas', keywords: %w[agenda reserva agendamento serviço horário] },
    { key: 'LANDING_PAGE', title: 'Landing Page', description: 'Página de conversão para campanhas de marketing',
      keywords: %w[landing campanha conversão lead cta] },
    { key: 'PORTAL_CONTEUDO', title: 'Portal de Conteúdo',
      description: 'Portal com publicação recorrente de artigos e vídeos', keywords: %w[portal blog conteúdo artigos vídeos] }
  ]

  operations = operations_data.map do |op|
    Operation.find_or_create_by!(key: op[:key]) do |record|
      record.title = op[:title]
      record.description = op[:description]
      record.keywords = op[:keywords]
      record.active = true
    end
  end
  puts "✅ Operações criadas/atualizadas: #{operations.map(&:key).join(', ')}"

  puts '🧩 Criando leads com mensagens e operações...'
  base_time = Time.current - 2.days
  leads_seed = [
    {
      name: 'Mariana Silva',
      company_name: 'Doces Mariana',
      phone: '5548991111111',
      source_type: 'whatsapp',
      source_id: '5548991111111',
      ig_username: 'marianadoces',
      has_site: false,
      intention: 'novo_site',
      instruction: 'descobrir_escopo',
      source_endpoint: 'message',
      desires: ['site exclusivo', 'vitrine de produtos'],
      discovery_level: 2,
      enchantment_level: 2,
      closing_level: 1,
      understands_goals: 'sim',
      likes_some_site: 'portfólio-01',
      sources: [
        { source_type: 'whatsapp', source_id: '5548991111111' },
        { source_type: 'instagram', source_id: 'marianadoces' }
      ].to_json,
      operation_key: 'SITE_INSTITUCIONAL'
    },
    {
      name: 'Pedro Santos',
      company_name: 'Santos Store',
      phone: '5548992222222',
      source_type: 'instagram',
      source_id: 'santosstore',
      ig_username: 'santosstore',
      has_site: true,
      site_url: 'https://santosstore.example',
      intention: 'migrar_para_ecommerce',
      instruction: 'avaliar_complexidade',
      source_endpoint: 'message',
      desires: ['carrinho de compras', 'pagamento integrado'],
      discovery_level: 3,
      enchantment_level: 2,
      closing_level: 2,
      understands_smart_navigation: 'sim',
      knows_whats_mod: 'apresentado',
      sources: [
        { source_type: 'instagram', source_id: 'santosstore' },
        { source_type: 'site', source_id: 'https://santosstore.example' }
      ].to_json,
      operation_key: 'E_COMMERCE'
    },
    {
      name: 'Aline Rocha',
      company_name: 'Studio Aline',
      phone: '5548993333333',
      source_type: 'site',
      source_id: 'form-9871',
      ig_username: 'studioaline',
      has_site: false,
      intention: 'app_agendamento',
      instruction: 'mapear_fluxos',
      source_endpoint: 'message',
      desires: ['agenda online', 'notificações whatsapp'],
      discovery_level: 2,
      enchantment_level: 3,
      closing_level: 2,
      understands_thats_exclusive: 'sim',
      knows_console_mod: 'sim',
      sources: [
        { source_type: 'site', source_id: 'form-9871' },
        { source_type: 'whatsapp', source_id: '5548993333333' }
      ].to_json,
      operation_key: 'APP_AGENDAMENTO'
    },
    {
      name: 'Carlos Mendes',
      company_name: 'Mendes Marketing',
      phone: '5548994444444',
      source_type: 'whatsapp',
      source_id: '5548994444444',
      ig_username: 'mendesmkt',
      has_site: true,
      site_url: 'https://mendesmkt.example',
      intention: 'campanha_lancamento',
      instruction: 'definir_copy',
      source_endpoint: 'message',
      desires: ['landing com CTA', 'integração analytics'],
      discovery_level: 3,
      enchantment_level: 3,
      closing_level: 2,
      validated_interest: 'sim',
      sources: [
        { source_type: 'whatsapp', source_id: '5548994444444' }
      ].to_json,
      operation_key: 'LANDING_PAGE'
    },
    {
      name: 'Bruna Lopes',
      company_name: 'Portal Saúde Já',
      phone: '5548995555555',
      source_type: 'instagram',
      source_id: 'saudeja',
      ig_username: 'saudeja',
      has_site: false,
      intention: 'portal_conteudo',
      instruction: 'definir_editoria',
      source_endpoint: 'message',
      desires: ['categorias de artigos', 'video player'],
      discovery_level: 2,
      enchantment_level: 4,
      closing_level: 2,
      received_proposal: 'enviada',
      sources: [
        { source_type: 'instagram', source_id: 'saudeja' }
      ].to_json,
      operation_key: 'PORTAL_CONTEUDO'
    }
  ]
  # Exemplos extras completos (Facebook, Chat, Reaction, Site)
  leads_seed += [
    {
      name: 'Lucia Prado',
      company_name: 'Lucia Prado Conteúdo',
      phone: '5521997777777',
      source_type: 'facebook',
      source_id: '100151666446451',
      fb_id: '100151666446451',
      fb_username: 'luciaprado',
      ig_username: 'luciaprado',
      has_site: false,
      intention: 'social_portal',
      instruction: 'planejar_editorial',
      source_endpoint: 'comment',
      desires: ['editorias claras', 'vídeos curtos'],
      discovery_level: 3,
      enchantment_level: 3,
      closing_level: 1,
      understands_thats_memorable: 'sim',
      sources: [
        { source_type: 'facebook', source_id: '100151666446451' },
        { source_type: 'instagram', source_id: 'luciaprado' }
      ].to_json,
      target_id: 'ROBOTRACK_FB_PAGE',
      execution_id: 'EXE-2025-001',
      operation_key: 'PORTAL_CONTEUDO'
    },
    {
      name: 'Atendimento Rio',
      company_name: 'Serviços Rio',
      phone: '5521990000000',
      source_type: 'chat',
      source_id: 'session-abc123',
      ig_username: nil,
      has_site: false,
      intention: 'app_agendamento',
      instruction: 'mapear_chamadas',
      source_endpoint: 'call',
      desires: ['agendamento por chamada', 'confirmação por whatsapp'],
      discovery_level: 2,
      enchantment_level: 3,
      closing_level: 2,
      understands_complexity: 'sim',
      sources: [
        { source_type: 'chat', source_id: 'session-abc123' },
        { source_type: 'whatsapp', source_id: '5521990000000' }
      ].to_json,
      target_id: 'ROBOTRACK_CHAT',
      execution_id: 'EXE-2025-002',
      operation_key: 'APP_AGENDAMENTO'
    },
    {
      name: 'Promo Mendes',
      company_name: 'Mendes Marketing',
      phone: '5548994444444',
      source_type: 'instagram',
      source_id: 'reaction_98765',
      ig_username: 'mendesmkt',
      has_site: true,
      site_url: 'https://mendesmkt.example',
      intention: 'campanha_reacao',
      instruction: 'capturar_engajamento',
      source_endpoint: 'reaction',
      desires: ['landing dinâmica', 'pixel'],
      discovery_level: 3,
      enchantment_level: 3,
      closing_level: 2,
      validated_interest: 'sim',
      sources: [
        { source_type: 'instagram', source_id: 'reaction_98765' },
        { source_type: 'whatsapp', source_id: '5548994444444' }
      ].to_json,
      target_id: 'ROBOTRACK_INSTAGRAM',
      execution_id: 'EXE-2025-003',
      operation_key: 'LANDING_PAGE'
    },
    {
      name: 'Warehouse Ecom',
      company_name: 'Warehouse LTDA',
      phone: '5548996666666',
      source_type: 'site',
      source_id: 'form-12345',
      ig_username: 'warehouse_ltda',
      has_site: true,
      site_url: 'https://warehouse.example',
      intention: 'ecommerce_full',
      instruction: 'orcar_migracao',
      source_endpoint: 'message',
      desires: ['cálculo de frete', 'estoque'],
      discovery_level: 3,
      enchantment_level: 2,
      closing_level: 2,
      understands_smart_navigation: 'sim',
      sources: [
        { source_type: 'site', source_id: 'form-12345' },
        { source_type: 'instagram', source_id: 'warehouse_ltda' }
      ].to_json,
      target_id: 'ROBOTRACK_SITE',
      execution_id: 'EXE-2025-004',
      operation_key: 'E_COMMERCE'
    }
  ]

  leads_seed = leads_seed.select do |seed|
    id = "#{seed[:source_type]}:#{seed[:source_id]}"
    (leads_only.empty? || leads_only.include?(id)) && !leads_skip.include?(id)
  end

  leads = []
  leads_seed.each_with_index do |seed, idx|
    op_key = seed.delete(:operation_key)
    op = Operation.find_by(key: op_key)

    unique_selector = { source_type: seed[:source_type], source_id: seed[:source_id] }
    lead = Lead.find_or_initialize_by(unique_selector)
    assignable = seed.merge(last_interaction_at: base_time + idx.hours)
    assignable.delete(:source_endpoint) unless lead.has_attribute?(:source_endpoint)
    assignable.delete(:fb_id) unless lead.has_attribute?(:fb_id)
    assignable.delete(:fb_username) unless lead.has_attribute?(:fb_username)
    assignable.delete(:igs_id) unless lead.has_attribute?(:igs_id)
    assignable.delete(:target_id) unless lead.has_attribute?(:target_id)
    assignable.delete(:execution_id) unless lead.has_attribute?(:execution_id)
    lead.assign_attributes(assignable)
    lead.save!
    lead.associate_with_operation_by_key(op.key) if op.present?

    if should_perform_lead_messages && lead.messages.count < 3
      msgs_time = base_time + idx.hours
      messages_data = [
        {
          lead_id: lead.id,
          sender_role: 'user',
          content: 'Olá! Quero entender melhor como vocês trabalham.',
          intention: 'discovery',
          instruction: 'coletar_contexto',
          content_type: 'text',
          source_message_id: SecureRandom.hex(8),
          created_at: msgs_time + 5.minutes
        },
        {
          lead_id: lead.id,
          sender_role: 'agent',
          agent_type: 'assistant',
          content: 'Legal! Me conte sobre seu objetivo principal e público.',
          intention: 'discovery',
          instruction: 'perguntas_criterios',
          content_type: 'text',
          source_message_id: SecureRandom.hex(8),
          created_at: msgs_time + 12.minutes
        },
        {
          lead_id: lead.id,
          sender_role: 'user',
          content: 'Quero algo memorável e fácil de navegar.',
          intention: 'enchantment',
          instruction: 'registrar_desejos',
          content_type: 'text',
          source_message_id: SecureRandom.hex(8),
          created_at: msgs_time + 20.minutes
        }
      ]

      variant = idx % 4
      messages_data << case variant
                       when 0
                         {
                           lead_id: lead.id,
                           sender_role: 'user',
                           content: 'Segue referência visual que gosto.',
                           intention: 'enchantment',
                           instruction: 'coletar_referencias',
                           content_type: 'image',
                           media_url: 'https://example.com/ref-visual.jpg',
                           media_mime: 'image/jpeg',
                           source_message_id: SecureRandom.hex(8),
                           created_at: msgs_time + 28.minutes
                         }
                       when 1
                         {
                           lead_id: lead.id,
                           sender_role: 'user',
                           content: 'Enviei um áudio com detalhes.',
                           intention: 'enchantment',
                           instruction: 'ouvir_audio',
                           content_type: 'audio',
                           media_url: 'https://example.com/detalhes.mp3',
                           media_mime: 'audio/mpeg',
                           source_message_id: SecureRandom.hex(8),
                           created_at: msgs_time + 28.minutes
                         }
                       when 2
                         {
                           lead_id: lead.id,
                           sender_role: 'user',
                           content: 'Veja este vídeo de referência.',
                           intention: 'enchantment',
                           instruction: 'assistir_video',
                           content_type: 'video',
                           media_url: 'https://example.com/ref.mp4',
                           media_mime: 'video/mp4',
                           source_message_id: SecureRandom.hex(8),
                           created_at: msgs_time + 28.minutes
                         }
                       else
                         {
                           lead_id: lead.id,
                           sender_role: 'user',
                           content: 'Anexei um PDF com requisitos.',
                           intention: 'closing',
                           instruction: 'avaliar_requisitos',
                           content_type: 'document',
                           media_url: 'https://example.com/requisitos.pdf',
                           media_mime: 'application/pdf',
                           source_message_id: SecureRandom.hex(8),
                           created_at: msgs_time + 28.minutes
                         }
                       end

      LeadMessage.create_bulk(messages_data)
    end

    leads << lead
  end

  operations.each(&:update_leads_count!)
  puts "✅ Leads criados: #{leads.size}"
end

if should_perform_users
  # Criar tipos de usuário padrão
  puts '📝 Criando tipos de usuário...'
  UserType.seed_default_types!

  # Criar usuário admin OG
  puts '👤 Criando usuário admin OG...'
  og_type = UserType.og || (UserType.seed_default_types!
                            UserType.og)
  raise 'Tipo de usuário OG ausente' if og_type.nil?

  admin_user = User.find_or_initialize_by(email: 'gui@polemk.com')
  admin_user.assign_attributes(
    name: 'Administrador',
    phone: '5548988051484',
    user_type: og_type,
    provider: nil,
    provider_uid: nil
  )
  begin
    admin_user.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️ Falha ao criar admin: #{e.message}"
  end
  puts "✅ Usuário admin criado: #{admin_user.email}"

  # Criar usuário cliente de teste
  puts '👤 Criando usuário cliente de teste...'
  client_type = UserType.client || (UserType.seed_default_types!
                                    UserType.client)
  raise 'Tipo de usuário client ausente' if client_type.nil?

  test_user = User.find_or_initialize_by(email: 'teste@example.com')
  test_user.assign_attributes(
    name: 'Usuário Teste',
    phone: '5548999999999',
    user_type: client_type,
    provider: nil,
    provider_uid: nil
  )
  begin
    test_user.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️ Falha ao criar usuário de teste: #{e.message}"
  end
  puts "✅ Usuário de teste criado: #{test_user.email}"
end

if should_perform_client_application
  # Client Applications padrão
  puts '🔐 Criando Client Applications...'
  begin
    default_apps = [
      { name: 'ASAAS', token: SecureRandom.hex(32) },
      { name: 'FRONTEND_PUBLIC', token: SecureRandom.hex(32) }
    ]

    default_apps.each do |app|
      ClientApplication.find_or_create_by!(name: app[:name]) do |record|
        record.token = app[:token]
        record.active = true
      end
    end
    puts '✅ Client Applications criados/atualizados'
  rescue StandardError => e
    puts "❌ Erro ao criar Client Applications: #{e.message}"
  end
end

# ==========================
# Plans & PlanFeatures Seeds
# ==========================

puts '📦 Criando planos e features...'

begin
  # Features padrão alinhadas ao tema do projeto (memória, navegação inteligente, suporte)
  features_data = [
    { title: 'Tema Dark/Light com Design Tokens',
      description: '<p>Interface moderna com alternância de tema e tokens de design.</p>', is_active: true },
    { title: 'Navegação Inteligente (Smart Navigation)',
      description: '<p>Arquitetura de rotas com carregamento rápido e estados claros.</p>', is_active: true },
    { title: 'Integração WhatsApp (Evolution)',
      description: '<p>Mensagens, webhooks e notificações em tempo real.</p>', is_active: true },
    { title: 'Integração Pagamentos (Asaas)', description: '<p>Base pronta para cobrança via PIX e cartão.</p>',
      is_active: true },
    { title: 'Console de Administração', description: '<p>Acesso ao console com roles e JWT.</p>', is_active: true },
    { title: 'Suporte Prioritário', description: '<p>Atendimento dedicado com SLAs.</p>', is_active: true }
  ]

  features = features_data.map.with_index(1) do |feat, idx|
    pf = PlanFeature.find_or_create_by!(title: feat[:title]) do |record|
      record.is_active = feat[:is_active]
      record.sort_order = idx
    end
    if feat[:description].present?
      pf.reload
      pf[:description] = feat[:description]
      pf.save!
    end
    pf
  end

  # Permissions padrão e mapeamento por título de feature
  perms_map = {
    'Tema Dark/Light com Design Tokens' => { key: 'theme_toggle', title: 'Alternar Tema' },
    'Navegação Inteligente (Smart Navigation)' => { key: 'smart_navigation', title: 'Navegação Inteligente' },
    'Integração WhatsApp (Evolution)' => { key: 'whats_integration', title: 'Integração WhatsApp' },
    'Integração Pagamentos (Asaas)' => { key: 'payments_integration', title: 'Integração Pagamentos' },
    'Console de Administração' => { key: 'console_access', title: 'Acesso ao Console' },
    'Suporte Prioritário' => { key: 'priority_support', title: 'Suporte Prioritário' }
  }

  features.each do |pf|
    pm = perms_map[pf.title]
    next unless pm

    perm = Permission.find_or_create_by!(key: pm[:key]) do |p|
      p.title = pm[:title]
      p.description = "Permissão gerada pela feature #{pf.title}"
    end
    PlanFeaturePermission.find_or_create_by!(plan_feature_id: pf.id, permission_id: perm.id)
  end

  # Plano de Assinatura (subscription)
  subscription_plan = Plan.find_or_initialize_by(identifier: 'SUB001')
  subscription_plan.assign_attributes(
    title: 'Robotrack Pro',
    site_title: 'Plano Pro — Robotrack',
    subtitle: 'Para projetos contínuos com evolução constante',
    price: 199.90,
    old_price: 249.90,
    pix_price: 189.90,
    installment_price: 199.90,
    max_installment_value: 49.90,
    max_installments_count: 12,
    is_free: false,
    is_popular: true,
    is_active: true,
    billing_kind: 'subscription',
    allows_console_access: true,
    color: '#6E56CF',
    sort_order: 1
  )
  subscription_plan.save!
  subscription_plan.reload
  subscription_plan[:description] = '<p>Assinatura completa com atualizações, integrações e suporte contínuo.</p>'
  subscription_plan.save!

  # Vincular features principais ao Pro com ordem
  pro_features_order = {
    'Tema Dark/Light com Design Tokens' => 1,
    'Navegação Inteligente (Smart Navigation)' => 2,
    'Integração WhatsApp (Evolution)' => 3,
    'Integração Pagamentos (Asaas)' => 4,
    'Console de Administração' => 5,
    'Suporte Prioritário' => 6
  }
  features.each do |pf|
    order = pro_features_order[pf.title] || pf.sort_order
    assignment = PlanFeatureAssignment.find_or_initialize_by(plan_id: subscription_plan.id, plan_feature_id: pf.id)
    assignment.sort_order = order
    assignment.save!
  end

  # Plano Pagamento Único (one_time)
  one_time_plan = Plan.find_or_initialize_by(identifier: 'ONE001')
  one_time_plan.assign_attributes(
    title: 'Robotrack Start',
    site_title: 'Plano Start — Robotrack',
    subtitle: 'Ideal para início com entrega rápida',
    price: 49.90,
    old_price: nil,
    pix_price: 44.90,
    installment_price: 49.90,
    max_installment_value: 49.90,
    max_installments_count: 1,
    is_free: false,
    is_popular: false,
    is_active: true,
    billing_kind: 'one_time',
    allows_console_access: false,
    color: '#12B981',
    sort_order: 2
  )
  one_time_plan.save!
  one_time_plan.reload
  one_time_plan[:description] = '<p>Pagamento único com entrega inicial e base integrada.</p>'
  one_time_plan.save!

  # Vincular features essenciais ao Start
  start_features = ['Tema Dark/Light com Design Tokens', 'Navegação Inteligente (Smart Navigation)',
                    'Integração WhatsApp (Evolution)']
  start_features.each.with_index(1) do |title, idx|
    pf = features.find { |f| f.title == title }
    next unless pf

    assignment = PlanFeatureAssignment.find_or_initialize_by(plan_id: one_time_plan.id, plan_feature_id: pf.id)
    assignment.sort_order = idx
    assignment.save!
  end

  puts "✅ Planos e features criados/atualizados: Pro=#{subscription_plan.id} Start=#{one_time_plan.id} Features=#{features.size}"
rescue ActiveRecord::RecordInvalid => e
  puts "❌ Erro de validação ao criar planos/features: #{e.message}"
rescue StandardError => e
  puts "🧨 Erro inesperado em seeds de planos/features: #{e.class} - #{e.message}"
end

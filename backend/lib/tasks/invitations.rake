# frozen_string_literal: true

# code-only-invites (DA-1) — reemissão do CÓDIGO dos convites pendentes.
#
# O link por token foi removido: um convite pendente que só havia sido entregue
# como LINK ficaria sem caminho. Como o código em claro só é exibido UMA vez (na
# criação) e o banco guarda apenas o HMAC, não dá para "recuperar" o código antigo
# — reemite-se um NOVO código para cada convite pendente e imprime-se (e-mail +
# código) para o dono repassar por fora. NADA é enviado automaticamente.
#
# Por workspace e sob RLS (convenção da casa: id explícito + `Tenant.with`), como
# `progress:recompute`. Para descobrir o `workspace_id`, use o próprio app (o
# contexto de workspace corrente) ou uma consulta como `robotrack_migrator`.
namespace :invitations do
  desc 'code-only-invites: reemite um CÓDIGO novo para cada convite PENDENTE do workspace e imprime (e-mail, código). Nada é enviado. Uso: rake invitations:reissue_codes[<workspace_id>]'
  task :reissue_codes, [:workspace_id] => :environment do |_t, args|
    workspace_id = args[:workspace_id] or abort('uso: rake invitations:reissue_codes[<workspace_id>]')

    reissued = []
    Tenant.with(workspace_id: workspace_id, user_id: nil) do
      # Só os PENDENTES (não usados) e ainda dentro da validade do convite: um
      # convite já consumido ou expirado não precisa de código novo.
      Invitation.pending.where('expires_at > now()').find_each do |inv|
        code = reissue_one!(inv)
        reissued << { email: inv.email, code: code }
      end
    end

    if reissued.empty?
      puts "Nenhum convite pendente no workspace #{workspace_id}. Nada a reemitir."
      next
    end

    puts "Reemitidos #{reissued.size} código(s) no workspace #{workspace_id} (validade 48h):"
    puts '(repasse cada código à pessoa por fora — o produto NÃO envia e-mail)'
    reissued.each { |r| puts format('  %-40s  %s', r[:email], r[:code]) }
  end
end

# Gera um código novo em claro, grava só o HMAC, renova a validade do código e
# ZERA o lockout. `update_columns` evita callbacks/validações (o `token` já existe
# e permanece dormente). Retry curto contra colisão do índice único de `code_hash`.
def reissue_one!(inv)
  attempts = 0
  begin
    code = Invitation.generate_short_code
    inv.update_columns(
      code_hash: Invitation.code_hash_for(code),
      code_expires_at: Time.current + Invitation::CODE_VALIDITY,
      code_attempts: 0,
      code_locked_at: nil,
      updated_at: Time.current
    )
    code.gsub(/(.{4})(.{4})/, '\1-\2')
  rescue ActiveRecord::RecordNotUnique
    raise if (attempts += 1) > 5

    retry
  end
end

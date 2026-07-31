# frozen_string_literal: true

module Notifications
  # Renderiza a mensagem versionada (in-app-notifications 2.2 / §2.7). Objeto PURO:
  # escolhe a chave por `type`, grava o `format_version` usado, e — SÓ quando a msg
  # passa de 500 — trunca APENAS `%{comment}` com `…`, deixando descrição da tarefa
  # e nome do robô íntegros (a truncagem nunca corta o nome do robô).
  module MessageBuilder
    FORMAT_VERSION = 1
    MAX_LEN = 500
    # internationalization G6 (D-I5a) — o default é pt-BR, mas a msg é renderizada e
    # CONGELADA no locale do DESTINATÁRIO (o `CreateService` passa `locale:`). A
    # truncagem de `%{comment}` é recalculada no MESMO locale (o texto fixo tem
    # comprimento diferente por idioma).
    LOCALE = :'pt-BR'
    ELLIPSIS = '…'

    module_function

    # Devolve { msg:, format_version: }. `locale` = idioma do destinatário (default pt-BR).
    # `project`/`cell` situam a tarefa no caminho completo (projeto · célula · robô).
    def build(type:, author:, task:, robot:, project: nil, cell: nil, n: nil, comment: nil, assignee: nil, locale: LOCALE)
      key = "notifications.v#{FORMAT_VERSION}.#{type}"
      vars = { author: author, task: task, robot: robot, project: project, cell: cell,
               n: n, comment: comment, assignee: assignee }.compact

      msg = render(key, vars, locale)
      if msg.length > MAX_LEN && comment
        fixed = render(key, vars.merge(comment: ''), locale).length
        room = [MAX_LEN - fixed - ELLIPSIS.length, 0].max
        msg = render(key, vars.merge(comment: comment[0, room] + ELLIPSIS), locale)
      end

      { msg: msg, format_version: FORMAT_VERSION }
    end

    # notification-preferences G6 (§D-P8) — mensagem de evento ESTRUTURAL. O enum
    # da coluna é sempre 'structure'; a subchave `structure.<entity>.<action>`
    # escolhe o texto (ação + entidade no texto, não no enum). Sem `%{comment}` a
    # truncar; ainda assim o rótulo é limitado a 500 por defesa contra a CHECK
    # `msg_max_500` (nomes de entidade são ≤120, então a truncagem quase nunca
    # dispara). `entity`/`action` já vêm normalizados pelo chamador.
    def build_structure(entity:, action:, author:, label:, parent: nil, locale: LOCALE)
      key = "notifications.v#{FORMAT_VERSION}.structure.#{entity}.#{action}"
      vars = { author: author, label: label, parent: parent }.compact
      msg = render(key, vars, locale)
      msg = "#{msg[0, MAX_LEN - ELLIPSIS.length]}#{ELLIPSIS}" if msg.length > MAX_LEN
      { msg: msg, format_version: FORMAT_VERSION }
    end

    def render(key, vars, locale = LOCALE)
      I18n.t(key, locale: locale, **vars)
    end
  end
end

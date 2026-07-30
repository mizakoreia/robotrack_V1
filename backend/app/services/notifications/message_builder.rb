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
    def build(type:, author:, task:, robot:, n: nil, comment: nil, assignee: nil, locale: LOCALE)
      key = "notifications.v#{FORMAT_VERSION}.#{type}"
      vars = { author: author, task: task, robot: robot, n: n, comment: comment, assignee: assignee }.compact

      msg = render(key, vars, locale)
      if msg.length > MAX_LEN && comment
        fixed = render(key, vars.merge(comment: ''), locale).length
        room = [MAX_LEN - fixed - ELLIPSIS.length, 0].max
        msg = render(key, vars.merge(comment: comment[0, room] + ELLIPSIS), locale)
      end

      { msg: msg, format_version: FORMAT_VERSION }
    end

    def render(key, vars, locale = LOCALE)
      I18n.t(key, locale: locale, **vars)
    end
  end
end

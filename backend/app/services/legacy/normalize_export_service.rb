# frozen_string_literal: true

require 'json'

module Legacy
  # legacy-data-migration 3.1-3.3 (§4.4, D-LDM-1, D-LDM-3 camada 1) — o pré-processador
  # OFFLINE que substitui as duas migrações estruturais de runtime do legado por uma
  # transformação PURA arquivo→arquivo. NÃO é código disparado por leitura: roda uma vez,
  # no `rake legacy:normalize[entrada,saida]`, antes do import.
  #
  # O que faz (idempotente — rodar sobre um arquivo já canônico reproduz os mesmos bytes):
  #   1. PROMOVE `workspace.projects` e `workspace.logs` a coleções de TOPO, carimbando
  #      `workspaceId` em cada item e REMOVENDO as chaves aninhadas (§4.4). Se já vierem
  #      no topo, não há migração a aplicar (`migracoes_aplicadas: 0`).
  #   2. REMOVE o sentinela "Não Atribuído" de `responsibles`, de todo `assignees` e de
  #      `resp` (camada 1 das 3 de D-LDM-3 — a 2 é o resolver, a 3 é a CHECK do banco).
  #   3. Emite `schemaVersion: 1` como PRIMEIRA chave e exige `ownerUid` (procedência).
  #
  # Idempotência sem canonicalização profunda: só as chaves de TOPO e de `workspace` têm
  # ordem fixada aqui; o conteúdo aninhado passa preservando a ordem original (o `merge`
  # atualiza a chave no lugar, sem reordenar). Assim raw→a→b dá SHA-256 idêntico.
  module NormalizeExportService
    Error = Class.new(StandardError)

    SENTINELS = ['não atribuído', 'nao atribuido'].freeze

    module_function

    # raw: Hash já parseado do export bruto. Devolve { canonical:, report: }. Levanta
    # Legacy::NormalizeExportService::Error (sem escrever nada) em entrada inválida.
    def normalize(raw)
      ws = raw['workspace']
      raise Error, 'workspace ausente no export' unless ws.is_a?(Hash)

      owner = ws['ownerUid'].to_s
      raise Error, 'ownerUid ausente — procedência do export não verificável' if owner.strip.empty?

      wsid = ws['id']
      counters = { sentinela: 0 }

      nested_projects = ws['projects']
      nested_logs     = ws['logs']
      migracoes = [nested_projects, nested_logs].count { |v| !v.nil? }

      projects = Array(raw['projects'] || nested_projects).map do |p|
        scrub_project(stamp(p, wsid), counters)
      end
      logs = Array(raw['logs'] || nested_logs).map do |entry|
        validate_log!(entry)
        stamp(entry, wsid)
      end

      responsibles = Array(ws['responsibles']).reject do |name|
        sentinel?(name).tap { |hit| counters[:sentinela] += 1 if hit }
      end

      canonical = build_canonical(raw, ws, owner, wsid, responsibles, projects, logs)
      report = {
        migracoes_aplicadas: migracoes,
        sentinela_removido: counters[:sentinela],
        entrada_ja_canonica: raw['schemaVersion'] == 1
      }
      { canonical: canonical, report: report }
    end

    # Transformação path→path com atomicidade (D-LDM-1): escreve num temporário e faz
    # rename (atômico no mesmo filesystem). Uma falha ANTES do rename não deixa o arquivo
    # de saída em disco (nem vazio, nem parcial); a `normalize` levanta antes de chegar
    # aqui em entrada inválida, então o modo de falha do §4.4 (log sem `ts`) também não
    # deixa saída. Devolve o report.
    def call(input_path:, output_path:)
      raw = JSON.parse(File.read(input_path, encoding: 'UTF-8'))
      result = normalize(raw) # pode levantar — nenhum arquivo tocado ainda
      write_atomic(result[:canonical], output_path)
      result[:report]
    end

    def write_atomic(canonical, output_path)
      json = JSON.pretty_generate(canonical)
      tmp = "#{output_path}.tmp.#{Process.pid}"
      File.write(tmp, json)
      File.rename(tmp, output_path)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end

    # --- internos ---

    # `workspace` reconstruído em ordem FIXA e SEM `projects`/`logs` (campos antigos não
    # são copiados — §4.4). `defaultTasks` preservado como veio.
    def build_canonical(raw, ws, owner, wsid, responsibles, projects, logs)
      workspace = {
        'id' => wsid, 'ownerUid' => owner, 'name' => ws['name'],
        'responsibles' => responsibles, 'defaultTasks' => ws['defaultTasks'] || []
      }

      canonical = { 'schemaVersion' => 1 }
      canonical['exportedAt'] = raw['exportedAt'] if raw.key?('exportedAt')
      canonical['workspace'] = workspace
      canonical['projects'] = projects
      canonical['logs'] = logs
      canonical['members'] = raw['members'] if raw.key?('members')
      canonical['notifications'] = raw['notifications'] if raw.key?('notifications')
      canonical
    end

    def stamp(obj, wsid)
      obj.merge('workspaceId' => wsid) # atualiza no lugar se já existir (idempotente)
    end

    # Remove o sentinela de `assignees`/`resp` de cada tarefa, preservando a ordem das
    # chaves (merge no lugar). Só reconstrói o que existe: `cells: null` fica `null`.
    def scrub_project(project, counters)
      cells = project['cells']
      return project unless cells.is_a?(Array)

      new_cells = cells.map do |cell|
        robots = cell['robots']
        next cell unless robots.is_a?(Array)

        new_robots = robots.map do |robot|
          tasks = robot['tasks']
          next robot unless tasks.is_a?(Array)

          robot.merge('tasks' => tasks.map { |t| scrub_task(t, counters) })
        end
        cell.merge('robots' => new_robots)
      end
      project.merge('cells' => new_cells)
    end

    # Só toca as chaves que a tarefa REALMENTE tem (não injeta `assignees`/`resp` em
    # quem não os declarava) e só reconstrói se houver mudança — mantém a ordem das
    # chaves e a idempotência byte a byte.
    def scrub_task(task, counters)
      changes = {}
      if task.key?('assignees')
        changes['assignees'] = Array(task['assignees']).reject do |n|
          sentinel?(n).tap { |hit| counters[:sentinela] += 1 if hit }
        end
      end
      if task.key?('resp') && sentinel?(task['resp'])
        counters[:sentinela] += 1
        changes['resp'] = nil
      end
      changes.empty? ? task : task.merge(changes)
    end

    def validate_log!(entry)
      return if entry.is_a?(Hash) && entry['ts'].to_s.strip != ''

      raise Error, "entrada de log sem `ts` — normalização abortada (nenhum arquivo escrito): #{entry.inspect}"
    end

    def sentinel?(name)
      return false if name.nil?

      SENTINELS.include?(name.to_s.strip.downcase)
    end
  end
end

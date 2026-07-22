# frozen_string_literal: true

# progress-rollup 5.1 — dump do progress_cache antes de um recálculo em massa
# sobre dado importado, e recálculo manual em massa. Ambos por workspace.
namespace :progress do
  desc 'Dump do progress_cache dos 3 níveis de um workspace para arquivo (verificação pré-destrutiva)'
  task :dump_cache, [:workspace_id, :path] => :environment do |_t, args|
    workspace_id = args[:workspace_id] or abort('uso: rake progress:dump_cache[<workspace_id>,<path>]')
    path = args[:path] || Rails.root.join("tmp/progress_cache_dump_#{workspace_id}.jsonl").to_s
    counts = Progress::CacheDump.call(workspace_id: workspace_id, path: path)
    puts "dump escrito em #{path}"
    counts.each { |level, n| puts "  #{level}: #{n} linhas" }
  end

  desc 'Recálculo em massa do progress_cache de um workspace (3 statements)'
  task :recompute, [:workspace_id] => :environment do |_t, args|
    workspace_id = args[:workspace_id] or abort('uso: rake progress:recompute[<workspace_id>]')
    Tenant.with(workspace_id: workspace_id, user_id: nil) do
      Progress::BulkRecompute.call(workspace_id: workspace_id)
    end
    puts "progress_cache recalculado para o workspace #{workspace_id}"
  end
end

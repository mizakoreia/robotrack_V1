import { useRealtimeStore } from '@/store/realtimeStore'

// realtime-collaboration 7.3 / D6.6 — o indicador de transporte da topbar. O modo
// precisa ser VISÍVEL: sem isso, um `/cable` mal roteado degrada 100% das sessões
// e ninguém percebe. `live`/`connecting` não mostram nada (o silêncio é o estado
// saudável); `degraded` e `offline` aparecem, e o teto de represamento (6.3)
// acrescenta "não sincronizado" — degradação HONESTA.
export function ConnectionIndicator() {
  const transport = useRealtimeStore((s) => s.transport)
  const synced = useRealtimeStore((s) => s.synced)

  if (transport === 'live' || transport === 'connecting') return null

  const label =
    transport === 'offline'
      ? 'Sem conexão'
      : synced
        ? 'Atualizando periodicamente'
        : 'Atualizando periodicamente · não sincronizado'

  return (
    <span
      role="status"
      aria-live="polite"
      className="label-sm inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-text-muted"
      data-transport={transport}
    >
      <span
        aria-hidden="true"
        className={
          transport === 'offline'
            ? 'h-1.5 w-1.5 rounded-full bg-text-muted'
            : 'h-1.5 w-1.5 rounded-full bg-warning'
        }
      />
      {label}
    </span>
  )
}

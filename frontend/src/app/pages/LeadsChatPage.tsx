import { useEffect, useMemo, useState } from 'react'
import { leadsApi, leadMessagesApi } from '@/lib/api/endpoints'
import type { Lead, LeadMessage } from '@/lib/api/types'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useChannel } from '@/hooks/useCable'
import { Send, Search } from 'lucide-react'

export function LeadsChatPage() {
  const [selected, setSelected] = useState<string>('')
  const [search, setSearch] = useState('')
  const [message, setMessage] = useState('')
  const [criteriaTab, setCriteriaTab] = useState<'enchantment' | 'closing'>('enchantment')
  const queryClient = useQueryClient()
  const listQ = useQuery<Lead[]>({ queryKey: ['leads', search], queryFn: () => leadsApi.list({ q: search, l: 50 }) })
  const messagesQ = useQuery<LeadMessage[]>({ queryKey: ['lead-messages', selected], queryFn: () => selected ? leadMessagesApi.list(selected, { l: 200 }) : Promise.resolve([]), enabled: !!selected, refetchOnMount: true, refetchOnReconnect: true })
  const leadDetailsQ = useQuery<Lead | null>({ queryKey: ['lead-details', selected], queryFn: () => selected ? leadsApi.get(selected) : Promise.resolve(null), enabled: !!selected, refetchOnMount: true, refetchOnReconnect: true })

  const sendMutation = useMutation({
    mutationFn: async () => {
      if (!selected || !message.trim()) return
      return leadMessagesApi.create(selected, { sender_role: 'agent', content: message.trim() })
    },
    onSuccess: () => {
      setMessage('')
      queryClient.invalidateQueries({ queryKey: ['lead-messages', selected] })
    }
  })

  useChannel('LeadChatChannel', { lead_id: selected }, {
    received: (evt: any) => {
      if (evt?.type === 'message_created' && (evt.lead_smart_id === selected || String(evt.lead_id) === selected)) {
        queryClient.invalidateQueries({ queryKey: ['lead-messages', selected] })
      }
    }
  })

  useEffect(() => {
    if (!selected && listQ.data?.[0]) {
      const first = listQ.data[0]
      const key = first.smart_id || String(first.id) || first.session_uuid
      setSelected(key)
      queryClient.setQueryData(['lead-details', key], first)
    }
  }, [listQ.data])

  const currentLead = useMemo(() => (leadDetailsQ.data || listQ.data?.find(l => l.smart_id === selected || String(l.id) === selected)), [leadDetailsQ.data, listQ.data, selected])
  const enchQ = useMemo(() => Object.entries(currentLead?.enchantment_criteria_questions || {}), [currentLead])
  const closingQ = useMemo(() => Object.entries(currentLead?.closing_criteria_questions || {}), [currentLead])
  const enchCount = currentLead?.enchantment_criteria_count || 0
  const closingCount = currentLead?.closing_criteria_count || 0

  const stageBadge = (stage: Lead['current_stage']) => {
    const map: Record<string, { label: string; bg: string; fg: string }> = {
      discovery: { label: 'DISCOVERY', bg: 'bg-blue-900/40', fg: 'text-blue-300' },
      enchantment: { label: 'EM EDUCAÇÃO', bg: 'bg-emerald-900/40', fg: 'text-emerald-300' },
      closing: { label: 'APRESENTAÇÃO', bg: 'bg-purple-900/40', fg: 'text-purple-300' },
    }
    const s = map[stage] || map.discovery
    return (
      <span className={`inline-flex items-center gap-2 rounded-md px-2 py-1 text-[10px] font-semibold ${s.bg} ${s.fg} border border-border`}> 
        {s.label}
      </span>
    )
  }

  const daysSince = (iso?: string) => {
    if (!iso) return null
    const diff = Math.floor((Date.now() - new Date(iso).getTime()) / (1000*60*60*24))
    return `${diff} dias`
  }

  return (
    <div className="grid grid-cols-12 gap-4 h-[calc(100vh-122px)]">
      <aside className="col-span-3 rounded-xl bg-secondary/10 p-3 overflow-y-auto">
        <div className="flex items-center gap-2 mb-3">
          <Search className="h-4 w-4" />
          <input value={search} onChange={(e)=>setSearch(e.target.value)} placeholder="Buscar lead" className="flex-1 bg-transparent outline-none text-sm" />
        </div>
        <ul className="space-y-3">
          {listQ.data?.map((lead)=> (
            <li key={lead.smart_id}>
              <button onClick={()=>{
                const key = lead.smart_id || String(lead.id) || lead.session_uuid
                setSelected(key)
                queryClient.setQueryData(['lead-details', key], lead)
                queryClient.invalidateQueries({ queryKey: ['lead-details', key] })
                queryClient.invalidateQueries({ queryKey: ['lead-messages', key] })
              }} className={`w-full text-left rounded-xl p-3 bg-card hover:bg-accent`}>
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    {stageBadge(lead.current_stage)}
                    {lead.has_unread && <span className="inline-block h-2 w-2 rounded-full bg-red-500" />}
                  </div>
                  <span className="text-xs text-muted-foreground">{daysSince(lead.last_interaction_at) || ''}</span>
                </div>
                <div className="text-sm font-semibold tracking-wide">{(lead.smart_id || lead.session_uuid || String(lead.id))}</div>
                {lead.last_message_content && <div className="mt-2 text-xs text-muted-foreground line-clamp-2">{lead.last_message_content}</div>}
                <div className="mt-2 flex flex-wrap gap-2">
                  {lead.operation_key && <span className="inline-flex items-center gap-1 rounded-md border border-yellow-700 bg-yellow-900/20 px-2 py-0.5 text-[10px] text-yellow-300">🏆 {lead.operation_key?.toUpperCase()}</span>}
                </div>
              </button>
            </li>
          ))}
        </ul>
      </aside>

      <section className="col-span-6 rounded-xl bg-card flex flex-col h-full">
        <div className="p-3 border-b border-border flex items-center justify-between">
          <div className="font-semibold">Conversa {currentLead?.name || currentLead?.smart_id || ''}</div>
        </div>
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {messagesQ.data?.slice().reverse().map((m)=> (
            <div key={m.smart_id} className={`max-w-[70%] rounded-lg px-3 py-2 ${m.sender_role==='agent' ? 'bg-blue-500/20 ml-auto' : 'bg-muted'}`}>
              <div className="text-sm">{m.content}</div>
              <div className="text-[10px] text-muted-foreground mt-1">{new Date(m.created_at).toLocaleTimeString()}</div>
            </div>
          ))}
        </div>
        <div className="p-3 border-t border-border flex items-center gap-2">
          <input value={message} onChange={(e)=>setMessage(e.target.value)} placeholder="Escrever mensagem..." className="flex-1 bg-transparent outline-none" />
          <button onClick={()=>sendMutation.mutate()} className="rounded-full h-9 w-9 flex items-center justify-center bg-blue-600 text-white disabled:opacity-50" disabled={!message.trim() || !selected}>
            <Send className="h-4 w-4" />
          </button>
        </div>
      </section>

      <aside className="col-span-3 rounded-xl bg-secondary/10 p-3 overflow-y-auto">
        {currentLead ? (
          <div className="space-y-4 text-sm">
            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="font-semibold mb-2">Informações do Lead</div>
              <div className="space-y-1">
                <div className="text-xs text-muted-foreground">ID:</div>
                <div className="text-sm font-semibold">{currentLead.smart_id}</div>
                <div className="text-xs text-muted-foreground mt-2">Nome:</div>
                <div className="text-sm">{currentLead.name || '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">Telefone:</div>
                <div className="text-sm text-red-400">{currentLead.phone || '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">Instagram:</div>
                <div className="text-sm">{currentLead.ig_username ? `@${currentLead.ig_username}` : '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">E-mail:</div>
                <div className="text-sm">{currentLead.name || '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">Site:</div>
                <div className="text-sm">{currentLead.has_site ? (currentLead.site_url || 'Possui') : 'Não possui site'}</div>
                <div className="text-xs text-muted-foreground mt-2">Intenção:</div>
                <div className="text-sm">{currentLead.intention || '-'}</div>
              </div>
            </div>

            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="font-semibold mb-2">Origem e Rastreamento</div>
              <div className="space-y-1">
                <div className="text-xs text-muted-foreground">Origem:</div>
                <div className="text-sm">{currentLead.source_type || '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">ID Origem:</div>
                <div className="text-sm">{currentLead.source_id || '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">UTM5 Session:</div>
                <div className="text-sm">{currentLead.session_uuid || '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">Criado em:</div>
                <div className="text-sm">{currentLead.created_at ? new Date(currentLead.created_at).toLocaleString() : '-'}</div>
                <div className="text-xs text-muted-foreground mt-2">Última Interação:</div>
                <div className="text-sm">{currentLead.last_interaction_at ? new Date(currentLead.last_interaction_at).toLocaleString() : '-'}</div>
              </div>
            </div>

            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="font-semibold mb-2">Progresso</div>
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-xs text-muted-foreground">Estágio atual:
                  <span className="inline-flex items-center gap-2 rounded-md px-2 py-1 text-[10px] font-semibold bg-blue-900/40 text-blue-300 border border-border">{currentLead.stage_label || currentLead.current_stage}</span>
                </div>
                <div className="grid grid-cols-3 gap-3 mt-2">
                  {[
                    {label:'Discovery', val: currentLead.discovery_level, color:'bg-blue-500'},
                    {label:'Encantamento', val: currentLead.enchantment_level, color:'bg-purple-500'},
                    {label:'Fechamento', val: currentLead.closing_level, color:'bg-gray-500'},
                  ].map(({label,val,color})=> (
                    <div key={label} className="space-y-1">
                      <div className="text-xs text-muted-foreground">{label}</div>
                      <div className="h-2 w-full rounded-full bg-muted"><div className={`h-2 rounded-full ${color}`} style={{width: `${(val/5)*100}%`}} /></div>
                      <div className="text-[11px]">{val}/5</div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="font-semibold mb-2">Estatísticas</div>
              <div className="flex items-center gap-2 text-sm">Total de mensagens: <span className="inline-flex items-center rounded-md px-2 py-0.5 bg-secondary text-secondary-foreground text-xs">{currentLead.messages_count ?? '-'}</span></div>
            </div>

            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="font-semibold mb-2">Pontos Importantes</div>
              <div className="text-xs text-muted-foreground mb-2">Nenhum ponto importante registrado para este cliente ainda.</div>
              <div className="flex gap-2">
                <input className="flex-1 bg-transparent outline-none border border-border rounded-md px-2 py-1 text-sm" placeholder="Adicionar um ponto importante..." />
                <button className="btn btn-neutral text-xs">Adicionar</button>
              </div>
            </div>

            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="font-semibold mb-3">Estágio do Lead</div>
              <div className="grid grid-cols-3 gap-3">
                {[
                  {label:'Discovery', val: currentLead.discovery_level, active: currentLead.current_stage==='discovery'},
                  {label:'Encantamento', val: currentLead.enchantment_level, active: currentLead.current_stage==='enchantment'},
                  {label:'Fechamento', val: currentLead.closing_level, active: currentLead.current_stage==='closing'},
                ].map(({label,val,active})=> (
                  <div key={label} className={`rounded-md border ${active? 'border-primary bg-primary/10' : 'border-border bg-muted/10'} p-2`}> 
                    <div className={`text-sm ${active? 'text-primary' : ''}`}>{label}</div>
                    <div className="text-[11px] text-muted-foreground">Nível {val}/5</div>
                  </div>
                ))}
              </div>
            </div>

            <div className="rounded-lg border border-border bg-card p-3 shadow-sm">
              <div className="flex items-center justify-between mb-3">
                <div className="font-semibold">Critérios de Qualificação</div>
                <div className="flex items-center gap-2 text-xs">
                  <span className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 bg-blue-900/40 text-blue-300 border">{enchCount}/13</span>
                  <span className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 bg-green-900/40 text-green-300 border">{closingCount}/5</span>
                </div>
              </div>
              <div className="flex gap-2 mb-3">
                <button onClick={()=>setCriteriaTab('enchantment')} className={`rounded-md px-3 py-1 text-xs ${criteriaTab==='enchantment' ? 'bg-blue-600 text-white' : 'bg-muted text-foreground'}`}>Encantamento</button>
                <button onClick={()=>setCriteriaTab('closing')} className={`rounded-md px-3 py-1 text-xs ${criteriaTab==='closing' ? 'bg-green-600 text-white' : 'bg-muted text-foreground'}`}>Fechamento</button>
              </div>
              <div className="space-y-2">
                {(criteriaTab==='enchantment' ? enchQ : closingQ).map(([key,question])=> (
                  <div key={key} className="rounded-md border border-border bg-muted/10 p-2 flex items-center justify-between">
                    <div className="text-sm">{question}</div>
                    <button className="rounded-full h-6 w-6 flex items-center justify-center border border-border">+</button>
                  </div>
                ))}
              </div>
            </div>
          </div>
        ) : (
          <div className="text-sm text-muted-foreground">Selecione um lead</div>
        )}
      </aside>
    </div>
  )
}
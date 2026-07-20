import { useEffect, useState } from 'react'
import { Check, LogOut } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { toast } from 'sonner'
import PageHeader from '@/components/PageHeader'
import { instancesApi, webhooksApi } from '@/lib/api/endpoints'
import { useChannel } from '@/hooks/useCable'
import type { WhatsRealtimeEvent } from '@/lib/api/types'

export function WhatsappPage() {
  const [instanceInfo, setInstanceInfo] = useState<any>(null)
  const [qr, setQr] = useState<string | null>(null)
  const [qrLoading, setQrLoading] = useState(false)
  const [webhookUrl, setWebhookUrl] = useState('')
  const [connectionStatus, setConnectionStatus] = useState<string>('unknown')
  const [qrExpiresIn, setQrExpiresIn] = useState<number | null>(null)
  const instanceId = instanceInfo?.instance?.instance_id || instanceInfo?.instance?.data?.instanceId
  const [didConnect, setDidConnect] = useState(false)
  useEffect(() => {
    if (qr && typeof qrExpiresIn === 'number') {
      const timer = setInterval(() => {
        setQrExpiresIn((prev) => {
          if (typeof prev !== 'number') return prev
          const next = prev - 1
          if (next <= 0) {
            clearInterval(timer)
            setQr(null)
            return 0
          }
          return next
        })
      }, 1000)
      return () => clearInterval(timer)
    }
  }, [qr, qrExpiresIn])

  useEffect(() => {
    (async () => {
      try {
        const instance = await instancesApi.getInstance()
        setInstanceInfo({ instance })
        setConnectionStatus(String(instance?.connection_status || 'unknown'))
        if (instance?.qr_code) {
          setQr(instance.qr_code)
          if (instance?.qr_expires_at) {
            const exp = new Date(instance.qr_expires_at).getTime()
            const now = Date.now()
            const remaining = Math.max(0, Math.floor((exp - now) / 1000))
            setQrExpiresIn(remaining)
          }
        }
      } catch {}
    })()
  }, [])

  useEffect(() => {
    (async () => {
      if (!instanceInfo) return
      if (didConnect) return
      const s = String(connectionStatus || 'unknown').toLowerCase()
      if (s === 'open' || s === 'connected') return
      const num = instanceInfo?.instance?.number || instanceInfo?.instance?.raw_response?.number
      setQrLoading(true)
      try {
        const res = await instancesApi.connect(num || undefined)
        const data = res.data
        const initialQr = data?.base64 || data?.qrcode || data?.qrcodeBase64 || null
        if (initialQr) {
          setQr(initialQr)
        }
        setDidConnect(true)
      } catch {}
      setQrLoading(false)
    })()
  }, [instanceInfo, connectionStatus])

  useChannel('WhatsappInstanceChannel', { instance_id: instanceId }, {
    connected: () => {},
    disconnected: () => {},
    received: (data: WhatsRealtimeEvent) => {
      switch (data?.type) {
        case 'connection_update': {
          const status = String((data as any).status || 'unknown')
          setConnectionStatus(status)
          if (status.toLowerCase() === 'open' || status === 'connected') {
            setQr(null)
            setQrLoading(false)
          }
          break
        }
        case 'logout_instance': {
          setConnectionStatus('disconnected')
          setQr(null)
          setQrLoading(false)
          break
        }
        case 'qrcode_updated': {
          const ev = data as any
          const base64 = ev?.qr_code
          if (typeof base64 === 'string' && base64.length > 0) {
            setQr(base64)
          } else {
            setQr(null)
          }
          setQrExpiresIn(null)
          setQrLoading(false)
          break
        }
        default:
          break
      }
    }
  })

  useEffect(() => {
    const hooks = instanceInfo?.instance?.polemk_webhooks
    if (Array.isArray(hooks) && hooks.length > 0 && !webhookUrl) {
      const w = hooks[0]
      const base = (w?.raw_response && w.raw_response.webhook && w.raw_response.webhook.url) || ''
      if (base) {
        setWebhookUrl(base)
        return
      }
      const u = w?.url
      if (typeof u === 'string' && u.length > 0) {
        try {
          const parsed = new URL(u)
          const seg = parsed.pathname.split('/').filter(Boolean)
          if (seg.length > 0) seg.pop()
          const path = seg.length > 0 ? '/' + seg.join('/') : ''
          const computed = parsed.origin + path
          setWebhookUrl(computed)
        } catch {
          const parts = u.split('/')
          setWebhookUrl(parts.slice(0, -1).join('/'))
        }
      }
    }
  }, [instanceInfo, webhookUrl])

  // Sem polling/auto-connect: QR será atualizado por webhook (QRCODE_UPDATED); botão manual mantém fluxo

  // Sem polling: conexão em tempo real via Action Cable + atualizações de webhook

  

  const copy = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text)
      toast.success('Copiado para a área de transferência')
    } catch {
      toast.error('Não foi possível copiar')
    }
  }

  

  

  return (
    <div className="space-y-6">
      <PageHeader title="Instância WhatsApp" subtitle="Configuração de webhooks e status da integração" />

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">

          <div className="bg-card rounded-lg border border-border p-6">
            <h2 className="text-lg font-semibold text-foreground mb-4">Mensagens</h2>
            {Array.isArray(instanceInfo?.instance?.messages) && instanceInfo.instance.messages.length > 0 ? (
              <div className="space-y-3">
                {instanceInfo.instance.messages.map((m: any) => (
                  <div key={m.id} className="flex items-center gap-3">
                    <Input readOnly value={m.full_number} className="w-64" />
                    <Input readOnly value={m.message} className="flex-1" />
                    <Button variant="outline" onClick={() => copy(m.message)}>copiar</Button>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-muted-foreground">Sem mensagens registradas</div>
            )}
          </div>

          
        </div>

        <div className="space-y-6">
          <div className="bg-card rounded-lg border border-border p-6">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-2">
                  <h2 className="text-lg font-semibold text-foreground">Escaneie o QR code com seu smartphone</h2>
                  {(() => {
                    const s = String(connectionStatus || instanceInfo?.instance?.connection_status || 'unknown').toLowerCase()
                    if (s === 'open' || s === 'connected') {
                      return <span className="px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200">Conectada</span>
                    }
                    return null
                  })()}
                </div>
                <div className="flex items-center gap-2">
                  <Button size="icon" variant="outline" aria-label="Atualizar QR" onClick={async () => {
                    try {
                      setQrLoading(true)
                      const restartRes = await instancesApi.restart()
                      const restartData = restartRes.data
                      setQr(restartData?.base64 || null)
                      try {
                        const connectRes = await instancesApi.connect()
                        const connectData = connectRes.data
                        const nextQr = connectData?.base64 || connectData?.qrcode || connectData?.qrcodeBase64 || null
                        if (nextQr) setQr(nextQr)
                      } catch {}
                      try {
                        const inst = await instancesApi.getInstance()
                        setInstanceInfo((prev: any) => ({ ...prev, instance: inst }))
                        const id = inst?.instance_id || inst?.data?.instanceId
                        if (id) {
                          const cs = await instancesApi.connectionStatus(id)
                          setConnectionStatus(String(cs?.connection_status || 'unknown'))
                        }
                      } catch {}
                      toast.success('Instância reiniciada')
                    } catch (e: any) {
                      toast.error(e?.response?.data?.message || 'Falha ao reiniciar e atualizar QR')
                    }
                    setQrLoading(false)
                  }}>
                    ↻
                  </Button>
                </div>
              </div>
            <div className="border border-border rounded-lg p-4 bg-muted flex items-center justify-center min-h-[280px]">
              {(() => {
                const s = String(connectionStatus || instanceInfo?.instance?.connection_status || 'unknown').toLowerCase()
                if (s === 'open' || s === 'connected') {
                  return (
                    <div className="flex items-center gap-3 px-4 py-3 rounded-md border border-green-300 bg-green-50 dark:bg-green-900/20 text-green-800 dark:text-green-200">
                      <Check className="w-5 h-5" />
                      <div>
                        <div className="font-medium">Instância conectada</div>
                        <div className="text-sm text-green-700 dark:text-green-300">Tudo certo, não é necessário escanear o QR.</div>
                      </div>
                    </div>
                  )
                }
                if (qr) {
                  return <img src={qr.startsWith('data:') ? qr : `data:image/png;base64,${qr}`} alt="QR Code" className="mx-auto max-w-full" />
                }
                if (qrLoading) {
                  return <div className="text-muted-foreground">Carregando QR...</div>
                }
                return <div className="text-muted-foreground">QR Code não carregado</div>
              })()}
            </div>
            {qr && typeof qrExpiresIn === 'number' && (
              <div className="mt-2 text-xs text-muted-foreground">{qrExpiresIn > 0 ? `Expira em ${qrExpiresIn}s` : 'QR expirado, aguarde novo código...'}</div>
            )}
            <div className="mt-3 flex items-center justify-end">
              {(() => {
                const s = String(connectionStatus || instanceInfo?.instance?.connection_status || 'unknown').toLowerCase()
                if (s === 'open' || s === 'connected') {
                  return (
                    <Button variant="outline" className="border-red-300 text-red-700 hover:bg-red-50 dark:text-red-300" onClick={async () => {
                      try {
                        await instancesApi.logout()
                        toast.success('Instância desconectada')
                        setQr(null)
                        setQrLoading(false)
                        try {
                          const inst = await instancesApi.getInstance()
                          setInstanceInfo({ instance: inst })
                          setConnectionStatus(String(inst?.connection_status || 'unknown'))
                        } catch {}
                      } catch (e: any) {
                        toast.error(e?.response?.data?.message || 'Falha ao desconectar instância')
                      }
                    }}>
                      <LogOut className="w-4 h-4 mr-2" />
                      desconectar instância
                    </Button>
                  )
                }
                return null
              })()}
            </div>
            
          </div>
          <div className="bg-card rounded-lg border border-border p-6">
            <h2 className="text-lg font-semibold text-foreground mb-2">Configure webhooks</h2>
            <p className="text-muted-foreground text-sm mb-4">Informe a URL do seu webhook para receber eventos</p>
            <div className="flex items-center gap-3">
              <Input placeholder="https://example.com/whats/messages-upsert" value={webhookUrl} onChange={(e) => setWebhookUrl(e.target.value)} />
              <Button
                variant="secondary"
                onClick={async () => {
                  if (!webhookUrl) {
                    toast.error('Informe a URL do webhook')
                    return
                  }
                  try {
                    await webhooksApi.config({ url: webhookUrl, events: ['SEND_MESSAGE','MESSAGES_UPSERT','MESSAGES_UPDATE','CONNECTION_UPDATE','LOGOUT_INSTANCE','QRCODE_UPDATED'], webhookByEvents: true, webhookBase64: true })
                    try {
                      const inst = await instancesApi.getInstance()
                      setInstanceInfo((prev: any) => ({ ...prev, instance: inst }))
                      const id = inst?.instance_id || inst?.data?.instanceId
                      if (id) {
                        const cs = await instancesApi.connectionStatus(id)
                        setConnectionStatus(String(cs?.connection_status || 'unknown'))
                      }
                      setWebhookUrl(webhookUrl)
                    } catch {}
                    toast.success('Webhook configurado')
                  } catch (e: any) {
                    toast.error(e?.response?.data?.message || 'Falha ao configurar webhook')
                  }
                }}
              >salvar</Button>
            </div>
            <div className="mt-4 space-y-2">
              {Array.isArray(instanceInfo?.instance?.polemk_webhooks) && instanceInfo.instance.polemk_webhooks.length > 0 ? (
                instanceInfo.instance.polemk_webhooks.map((w: any) => (
                  <div key={w.id} className="flex items-center gap-3">
                    <Input readOnly value={w.url} className="flex-1" />
                    <Button variant="outline" onClick={() => copy(w.url)}>copiar</Button>
                  </div>
                ))
              ) : (
                <div className="text-muted-foreground">Sem webhooks configurados</div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

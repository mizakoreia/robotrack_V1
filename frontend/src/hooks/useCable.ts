import { useState, useEffect } from 'react'
import { createConsumer } from '@rails/actioncable'

const WS_URL = import.meta.env.VITE_WS_URL || (window.location.origin.replace('http', 'ws').replace('5173', '3000'))

export function useCable() {
  const [consumer, setConsumer] = useState<any>(null)

  useEffect(() => {
    const token = localStorage.getItem('access_token') || localStorage.getItem('token')

    let endpoint = WS_URL
    if (!endpoint.endsWith('/cable')) {
      endpoint = endpoint.replace(/\/+$/, '') + '/cable'
    }
    const sep = endpoint.includes('?') ? '&' : '?'
    const url = token ? `${endpoint}${sep}token=${token}` : endpoint
    const cableConsumer = createConsumer(url)
    setConsumer(cableConsumer)

    return () => {
      cableConsumer.disconnect()
    }
  }, [])

  return consumer
}

export function useChannel(
  channelName: string,
  params: Record<string, any> = {},
  handlers?: {
    connected?: () => void
    disconnected?: () => void
    received?: (data: any) => void
  }
) {
  const [subscription, setSubscription] = useState<any>(null)
  const consumer = useCable()
  const attemptsRef = (globalThis as any).__ac_attemptsRef ??= { current: 0 }
  const timerRef = (globalThis as any).__ac_timerRef ??= { current: null as any }

  useEffect(() => {
    if (!consumer) return
    const paramValues = Object.values(params || {})
    const hasMissing = paramValues.some((v) => v === undefined || v === null || (typeof v === 'string' && v.length === 0))
    if (hasMissing) return

    const sub = consumer.subscriptions.create(
      { channel: channelName, ...params },
      {
        connected() {
          attemptsRef.current = 0
          if (handlers?.connected) handlers.connected()
        },
        disconnected() {
          if (handlers?.disconnected) handlers.disconnected()
          attemptsRef.current += 1
          const delay = Math.min(30000, 1000 * Math.pow(2, attemptsRef.current))
          try { if (timerRef.current) clearTimeout(timerRef.current) } catch {}
          timerRef.current = setTimeout(() => {
            if (!consumer) return
            try {
              const resub = consumer.subscriptions.create(
                { channel: channelName, ...params },
                {
                  connected() {
                    attemptsRef.current = 0
                    if (handlers?.connected) handlers.connected()
                  },
                  disconnected() {
                    if (handlers?.disconnected) handlers.disconnected()
                  },
                  received(data: any) {
                    if (handlers?.received) handlers.received(data)
                  },
                }
              )
              setSubscription(resub)
            } catch {}
          }, delay)
        },
        received(data: any) {
          if (handlers?.received) handlers.received(data)
        },
      }
    )

    setSubscription(sub)

    return () => {
      sub.unsubscribe()
      try { if (timerRef.current) clearTimeout(timerRef.current) } catch {}
    }
  }, [consumer, channelName, JSON.stringify(params)])

  return subscription
}

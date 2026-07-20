import React, { useEffect, useMemo, useState } from 'react'
import { Input } from '@/components/ui/Input'
import { cn } from '@/lib/utils'
import { apiClient } from '@/lib/api/client'

type Country = { name: string; iso2: string; dial_code: string }

interface PhoneInputGroupProps {
  value?: string
  onChange: (normalized: string) => void
  disabled?: boolean
  className?: string
  defaultIso2?: string
  containerClassName?: string
  allowErase?: boolean
}

export function PhoneInputGroup({ value, onChange, disabled, className, defaultIso2 = 'BR', containerClassName, allowErase }: PhoneInputGroupProps) {
  const [countries, setCountries] = useState<Country[]>([])
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [country, setCountry] = useState<Country | null>(null)
  const [localDigits, setLocalDigits] = useState('')

  const DEFAULT_COUNTRIES: Country[] = [
    { name: 'Brazil', iso2: 'BR', dial_code: '55' },
    { name: 'United States', iso2: 'US', dial_code: '1' },
    { name: 'Portugal', iso2: 'PT', dial_code: '351' },
    { name: 'Spain', iso2: 'ES', dial_code: '34' },
    { name: 'Argentina', iso2: 'AR', dial_code: '54' },
    { name: 'Mexico', iso2: 'MX', dial_code: '52' }
  ]

  useEffect(() => {
    const load = async () => {
      try {
        const data = await apiClient.get<{ countries: Country[] }>(`/api/v1/countries${query ? `?q=${encodeURIComponent(query)}` : ''}`)
        const list = (data?.countries || [])
        setCountries(list.length > 0 ? list : DEFAULT_COUNTRIES)
      } catch {
        setCountries(DEFAULT_COUNTRIES)
      }
    }
    load()
  }, [query])

  useEffect(() => {
    if (!country) {
      const br = countries.find((c) => c.iso2 === defaultIso2)
      if (br) setCountry(br)
    }
  }, [countries, country, defaultIso2])

  useEffect(() => {
    const digits = (value || '').replace(/\D/g, '')
    if (!digits) {
      setLocalDigits('')
      return
    }
    const matched = countries.find((c) => digits.startsWith(c.dial_code))
    if (matched) {
      setCountry(matched)
      setLocalDigits(digits.slice(matched.dial_code.length))
    } else if (country) {
      setLocalDigits(digits.slice(country.dial_code.length))
    }
  }, [value, countries])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return countries
    return countries.filter((c) => c.name.toLowerCase().includes(q) || c.iso2.toLowerCase().includes(q) || c.dial_code.startsWith(q.replace('+', '')))
  }, [countries, query])

  const flagSrc = (iso2: string) => {
    const cps = Array.from(iso2.toUpperCase()).map((c) => (0x1f1e6 + (c.charCodeAt(0) - 65)).toString(16)).join('-')
    return `https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/${cps}.svg`
  }

  const flagEmoji = (iso2: string) => {
    const codes = Array.from(iso2.toUpperCase()).map((c) => 0x1f1e6 + (c.charCodeAt(0) - 65))
    return String.fromCodePoint(...codes)
  }

  const [brokenFlags, setBrokenFlags] = useState<Record<string, boolean>>({})

  const formatDisplay = () => {
    if (!country) return ''
    const ddd = localDigits.slice(0, 2)
    const rest = localDigits.slice(2)
    if (!localDigits) return ''
    if (rest.length <= 0) return `(${ddd})`
    if (rest.length <= 4) return `(${ddd}) ${rest}`
    if (rest.length <= 8) return `(${ddd}) ${rest.slice(0, 4)}-${rest.slice(4)}`
    return `(${ddd}) ${rest.slice(0, 1)} ${rest.slice(1, 5)}-${rest.slice(5, 9)}`
  }

  const handleLocalChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value.replace(/\D/g, '')
    if (!raw && allowErase) {
      setLocalDigits('')
      try { onChange('') } catch {}
      return
    }
    let local = raw
    if (country && raw.startsWith(country.dial_code)) {
      local = raw.slice(country.dial_code.length)
    }
    local = local.slice(0, 11)
    setLocalDigits(local)
    if (country) onChange(`${country.dial_code}${local}`)
  }

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Backspace') return
    const formatted = formatDisplay()
    const start = (e.currentTarget.selectionStart ?? formatted.length)
    const end = (e.currentTarget.selectionEnd ?? start)
    const digitsBeforeStart = formatted.slice(0, start).replace(/\D/g, '').length
    const digitsBeforeEnd = formatted.slice(0, end).replace(/\D/g, '').length
    let next = localDigits
    if (start !== end) {
      next = localDigits.slice(0, digitsBeforeStart) + localDigits.slice(digitsBeforeEnd)
    } else {
      const idx = digitsBeforeStart - 1
      if (idx >= 0) next = localDigits.slice(0, idx) + localDigits.slice(idx + 1)
    }
    e.preventDefault()
    setLocalDigits(next)
    if (allowErase && next.length === 0) {
      try { onChange('') } catch {}
    } else if (country) {
      onChange(`${country.dial_code}${next}`)
    }
  }

  const selectCountry = (c: Country) => {
    setCountry(c)
    setOpen(false)
    onChange(`${c.dial_code}${localDigits}`)
  }

  const clearPhone = () => {
    setLocalDigits('')
    try { onChange('') } catch {}
  }

  return (
    <div className={cn('relative', className)}>
      <div className={cn('flex items-center gap-2 rounded-md h-10 px-3 py-2 border border-input bg-background', containerClassName)}>        
        <button type="button" disabled={disabled} onClick={() => setOpen((v) => !v)} className={cn('flex items-center gap-2 px-2 py-1 rounded-md hover:bg-accent', disabled && 'opacity-70 cursor-not-allowed')}>          
          {country && (
            brokenFlags[country.iso2] ? (
              <span className="text-base relative top-[2px]">{flagEmoji(country.iso2)}</span>
            ) : (
              <img
                src={flagSrc(country.iso2)}
                alt={country.iso2}
                className="h-5 w-5 rounded-sm relative top-[2px]"
                onError={() => setBrokenFlags((b) => ({ ...b, [country.iso2]: true }))}
              />
            )
          )}
          <span className="text-sm text-foreground relative top-[2px]">{country ? `+${country.dial_code}` : '+--'}</span>
        </button>
        <Input type="tel" value={formatDisplay()} onChange={handleLocalChange} onKeyDown={handleKeyDown} placeholder="(00) 0 0000-0000" disabled={disabled} className="flex-1 bg-transparent border-none focus:ring-0 px-0 py-0" />
        {allowErase && localDigits && (
          <button type="button" onClick={clearPhone} className={cn('px-2 py-1 text-xs rounded-md hover:bg-accent text-muted-foreground')}>Limpar</button>
        )}
      </div>

      {open && (
        <div className="absolute z-20 mt-2 w-full max-h-64 overflow-auto rounded-lg border border-border bg-popover shadow-lg">
          <div className="p-2">
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar país ou DDI" />
          </div>
          <ul className="divide-y divide-border">
            {filtered.map((c) => (
              <li key={c.iso2}>
                <button type="button" className="w-full flex items-center justify-start gap-2 p-2 hover:bg-accent text-left" onClick={() => selectCountry(c)}>
                  {brokenFlags[c.iso2] ? (
                    <span className="text-base relative top-[2px]">{flagEmoji(c.iso2)}</span>
                  ) : (
                    <img
                      src={flagSrc(c.iso2)}
                      alt={c.iso2}
                      className="h-5 w-5 rounded-sm relative top-[2px]"
                      onError={() => setBrokenFlags((b) => ({ ...b, [c.iso2]: true }))}
                    />
                  )}
                  <span className="flex-1 text-sm text-foreground">{c.name}</span>
                  <span className="text-sm text-muted-foreground">+{c.dial_code}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

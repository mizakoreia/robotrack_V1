import { useEffect, useMemo, useRef, useState } from 'react'
import { useAuthStore } from '@/store/authStore'
import { authApi, usersApi } from '@/lib/api/endpoints'
import { apiClient } from '@/lib/api/client'
import { Input } from '@/components/ui/Input'
import { Button } from '@/components/ui/Button'
import { toast } from 'sonner'
import { Check, X, Shield, Upload, User, MapPin } from 'lucide-react'

// design-system 8.3 (D-DS-7) — o produto NÃO tem campo de texto rico (§2.4): a
// única entrada de texto livre é o comentário de avanco (<textarea> < 100 chars).
// A biografia do perfil virou <textarea> de texto plano e Slate/slate-react/
// slate-history foram DESINSTALADOS. Mantém a interface {value, onChange} para
// nao tocar no resto da pagina.
function RichTextEditor({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <textarea
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder="Escreva sua biografia..."
      className="w-full min-h-[160px] p-3 text-sm text-foreground bg-background border border-border rounded-md"
      spellCheck={false}
    />
  )
}

export function ProfilePage() {
  const user = useAuthStore((s) => s.user)
  const setUser = useAuthStore((s) => s.setUser!)
  const [original, setOriginal] = useState(user)
  const [values, setValues] = useState({
    name: user?.name || '',
    email: user?.email || '',
    phone: user?.phone || '',
    cpf_cnpj: (user as any)?.cpf_cnpj || '',
    avatar_url: user?.avatar_url || '',
    cep: (user as any)?.cep || '',
    street: (user as any)?.street || '',
    number: (user as any)?.number || '',
    complement: (user as any)?.complement || '',
    district: (user as any)?.district || '',
    city: (user as any)?.city || '',
    state: (user as any)?.state || ''
  })
  const [isSaving, setIsSaving] = useState(false)
  const [showActions, setShowActions] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const [uploading, setUploading] = useState(false)
  const [bio, setBio] = useState<string>((user as any)?.biography_html || (user as any)?.biography || (user as any)?.biography_text || '')
  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 2 * 1024 * 1024) { toast.error('Arquivo muito grande (máx. 2MB)'); return }
    setUploading(true)
    try {
      const form = new FormData()
      form.append('file', file)
      const data = await apiClient.post<{ url: string }>(
        '/api/v1/uploads/avatar',
        form,
        { headers: { 'Content-Type': 'multipart/form-data' } }
      )
      setValues((v) => ({ ...v, avatar_url: data.url }))
      toast.success('Avatar enviado')
    } catch {
      toast.error('Erro ao enviar avatar')
    }
    setUploading(false)
  }

  useEffect(() => {
    authApi.me().then((r) => {
      const u: any = r.data.user
      setOriginal(u)
      setValues({
        name: u.name || '',
        email: u.email || '',
        phone: u.phone || '',
        cpf_cnpj: (u as any).cpf_cnpj || '',
        avatar_url: u.avatar_url || '',
        cep: (u as any).cep || '',
        street: (u as any).street || '',
        number: (u as any).number || '',
        complement: (u as any).complement || '',
        district: (u as any).district || '',
        city: (u as any).city || '',
        state: (u as any).state || ''
      })
      setBio((u as any).biography_html || (u as any).biography || (u as any).biography_text || '')
      setUser(u)
    }).catch(() => {})
  }, [])

  const dirtyFields = useMemo(() => {
    const diff: Record<string, any> = {}
    if (!original) return diff
    ;(['name','email','phone','cpf_cnpj','avatar_url','cep','street','number','complement','district','city','state'] as const).forEach((k) => {

      const orig = (original as any)[k] || ''
      if (values[k] !== (orig || '')) diff[k] = values[k]
    })
    return diff
  }, [values, original])

  const bioDirty = useMemo(() => {
    const orig = (original as any)?.biography_html || (original as any)?.biography || (original as any)?.biography_text || ''
    return (bio || '') !== (orig || '')
  }, [bio, original])

  const actionsActive = useMemo(() => {
    return Object.keys(dirtyFields).length > 0 || bioDirty
  }, [dirtyFields, bioDirty])

  useEffect(() => {
    if (actionsActive) setShowActions(true)
  }, [actionsActive])

  const canEdit = useMemo(() => {
    return !!user // JWT presente já foi verificado no guard
  }, [user])


  const cancelEdit = () => {
    if (!original) return
    setValues({
      name: original.name || '',
      email: original.email || '',
      phone: original.phone || '',
      cpf_cnpj: (original as any).cpf_cnpj || '',
      avatar_url: original.avatar_url || '',
      cep: (original as any).cep || '',
      street: (original as any).street || '',
      number: (original as any).number || '',
      complement: (original as any).complement || '',
      district: (original as any).district || '',
      city: (original as any).city || '',
      state: (original as any).state || ''
    })
    setBio((original as any)?.biography_html || (original as any)?.biography || (original as any)?.biography_text || '')
    toast.info('Alterações canceladas')
    setShowActions(false)
  }

  const validate = () => {
    if ('email' in dirtyFields) {
      const e = values.email
      if (e && !/^.+@.+\..+$/.test(e)) return 'Email inválido'
    }
    if ('phone' in dirtyFields) {
      const p = values.phone
      if (p && !/^\d{10,15}$/.test(p)) return 'Telefone deve ter 10-15 dígitos'
    }
    if ('cpf_cnpj' in dirtyFields) {
      const d = values.cpf_cnpj
      if (d && !/^\d{11}$|^\d{14}$/.test(d.replace(/\D/g, ''))) return 'CPF/CNPJ inválido'
    }
    if ('cep' in dirtyFields) {
      const c = values.cep
      if (c && !/^\d{5}-?\d{3}$/.test(c)) return 'CEP inválido'
    }
    if ('state' in dirtyFields) {
      const s = values.state
      if (s && !/^[A-Za-z]{2}$/.test(s)) return 'Estado deve ter 2 letras'
    }
    if (values.name.trim().length === 0) return 'Nome é obrigatório'
    return null
  }

  const save = async () => {
    const err = validate()
    if (err) { toast.error(err); return }
    if (!Object.keys(dirtyFields).length && !bioDirty) { toast.info('Nada para salvar'); return }
    setIsSaving(true)
    setShowActions(false)
    try {
      let updated: any = original
      if (Object.keys(dirtyFields).length) {
        updated = (await authApi.updateMe(dirtyFields)).data.user
        setOriginal(updated)
        setUser(updated)
      }
      if (bioDirty && original?.id) {
        await usersApi.update(original.id, { biography: bio } as any)
        const refetched: any = (await authApi.me()).data.user
        setOriginal(refetched)
        setUser(refetched)
      }
      toast.success('Perfil atualizado com sucesso')
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao salvar')
      setShowActions(true)
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="w-full mt-[10px]">
      <h1 className="text-2xl font-semibold mb-2 mt-6">Meu Perfil</h1>
      <p className="text-sm text-muted-foreground mb-6">Gerencie suas informações pessoais</p>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="space-y-6">
          <div className="p-6 bg-card border border-border rounded-lg">
            <div className="flex flex-col items-center gap-2">
          <div className="relative">
          <div
            className={`h-24 w-24 rounded-full overflow-hidden border border-border bg-muted ${canEdit ? 'cursor-pointer' : ''}`}
            onClick={canEdit ? () => fileInputRef.current?.click() : undefined}
          >
            {values.avatar_url ? (
              <img src={values.avatar_url} alt="Avatar" className="h-full w-full object-cover" />
            ) : (
              <img src={`https://api.dicebear.com/7.x/initials/svg?seed=${encodeURIComponent(values.name || values.email || 'User')}`} alt="Avatar" className="h-full w-full object-cover" />
            )}
          </div>
          {canEdit && (
            <button
              type="button"
              className="absolute -bottom-2 -right-2 h-8 w-8 rounded-full bg-primary text-primary-foreground border border-border shadow-lg flex items-center justify-center hover:bg-primary/90"
              onClick={(e) => { e.stopPropagation(); fileInputRef.current?.click() }}
              disabled={uploading}
            >
              <Upload className="h-4 w-4" />
            </button>
          )}
          <input ref={fileInputRef} type="file" accept="image/*" onChange={handleAvatarFile} className="hidden" />
        </div>
        <p className="text-sm text-foreground">Foto de Perfil</p>
        <p className="text-xs text-muted-foreground">JPG, PNG ou GIF (máx. 2MB)</p>
            </div>
          </div>

          <div className="p-6 bg-card border border-border rounded-lg">
          <div className="flex items-center gap-2 mb-3">
            <div className="h-6 w-6 rounded-md bg-muted flex items-center justify-center"><Shield className="h-4 w-4" /></div>
            <p className="font-medium">Biografia</p>
          </div>
          <div className="space-y-2">
              <label className="block text-sm text-muted-foreground">Biografia</label>
              <RichTextEditor value={bio} onChange={setBio} />
          </div>
        </div>
        </div>

        <div className="space-y-6">
          <div className="p-6 bg-card border border-border rounded-lg">
            <div className="flex items-center gap-2 mb-4">
              <div className="h-6 w-6 rounded-md bg-muted flex items-center justify-center"><User className="h-4 w-4" /></div>
              <p className="font-medium">Informações Pessoais</p>
            </div>
            <div className="space-y-6">
        <Field
          label="Nome"
          value={values.name}
          placeholder="Seu nome completo"
          onChange={(v) => setValues((s) => ({ ...s, name: v }))}
        />
        <Field
          label="Email"
          value={values.email}
          placeholder="seu@email.com"
          onChange={(v) => setValues((s) => ({ ...s, email: v }))}
        />
        <Field
          label="WhatsApp"
          value={values.phone}
          placeholder="Digite seu WhatsApp (só números)"
          onChange={(v) => setValues((s) => ({ ...s, phone: v }))}
        />
        <Field
          label="CPF/CNPJ"
          value={values.cpf_cnpj}
          placeholder="Digite seu CPF ou CNPJ (só números)"
          onChange={(v) => setValues((s) => ({ ...s, cpf_cnpj: v }))}
        />
            </div>
          </div>
        </div>

        <div className="space-y-6">
          <div className="p-6 bg-card border border-border rounded-lg">
            <div className="flex items-center gap-2 mb-4">
              <div className="h-6 w-6 rounded-md bg-muted flex items-center justify-center"><MapPin className="h-4 w-4" /></div>
              <p className="font-medium">Endereço</p>
            </div>
            <div className="space-y-6">
              <Field label="CEP" value={values.cep} placeholder="Insira seu CEP" onChange={(v) => setValues((s) => ({ ...s, cep: v }))} />
              <Field label="Rua/Avenida" value={values.street} placeholder="ex: Avenida Paulista" onChange={(v) => setValues((s) => ({ ...s, street: v }))} />
              <Field label="Número" value={values.number} placeholder="ex: 1000" onChange={(v) => setValues((s) => ({ ...s, number: v }))} />
              <Field label="Complemento" value={values.complement} placeholder="ex: Apto 123" onChange={(v) => setValues((s) => ({ ...s, complement: v }))} />
              <Field label="Bairro" value={values.district} placeholder="ex: Centro" onChange={(v) => setValues((s) => ({ ...s, district: v }))} />
              <Field label="Cidade" value={values.city} placeholder="ex: São Paulo" onChange={(v) => setValues((s) => ({ ...s, city: v }))} />
              <Field label="Estado" value={values.state} placeholder="UF (ex: SP)" onChange={(v) => setValues((s) => ({ ...s, state: v.toUpperCase() }))} />
            </div>
          </div>
        </div>

        <FloatingActions
          active={actionsActive && showActions}
          onSave={save}
          onCancel={cancelEdit}
          isSaving={isSaving}
        />
      </div>
    </div>
  )
}

function Field({ label, value, onChange, placeholder }: {
  label: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
}) {
  return (
    <div>
      <label className="block text-sm text-muted-foreground mb-1">{label}</label>
      <div className="relative">
        <Input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} />
      </div>
    </div>
  )
}

function FloatingActions({ active, onSave, onCancel, isSaving }: {
  active: boolean
  onSave: () => void
  onCancel: () => void
  isSaving: boolean
}) {
  const [render, setRender] = useState(active)
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    if (active) {
      setRender(true)
      const t = setTimeout(() => setVisible(true), 10)
      return () => clearTimeout(t)
    } else {
      setVisible(false)
      const t = setTimeout(() => setRender(false), 300)
      return () => clearTimeout(t)
    }
  }, [active])
  if (!render) return null
  return (
    <div className="fixed inset-x-0 bottom-6 z-50" data-helper>
      <div className={`helper-fab absolute bottom-0 left-1/2 -translate-x-1/2 flex items-center gap-2 transition-all duration-300 ${visible ? 'ease-out opacity-100 translate-y-0' : 'ease-in opacity-0 translate-y-4'}`}>
        <Button onClick={onSave} disabled={isSaving} variant="uiverse" className="px-3.5 py-1.5 text-[0.875rem] h-10">
          <span className="inline-flex items-center gap-1">
            <Check className="h-4 w-4" /> SALVAR
          </span>
        </Button>
        <Button onClick={onCancel} variant="uiverse" className="btn-neutral px-3.5 py-1.5 text-[0.875rem] h-10">
          <span className="inline-flex items-center gap-1">
            <X className="h-4 w-4" /> CANCELAR
          </span>
        </Button>
      </div>
    </div>
  )
}

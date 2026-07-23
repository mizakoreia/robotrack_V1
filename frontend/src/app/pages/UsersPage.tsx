import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, Filter, Eye, Pencil, Trash2, Plus, MoreHorizontal, X, Mail, Phone, Upload, Check } from 'lucide-react'
import PageHeader from '@/components/PageHeader'
import { usersApi } from '@/lib/api/endpoints'
import { apiClient } from '@/lib/api/client'
import { User } from '@/lib/api/types'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { PhoneInputGroup } from '@/components/PhoneInputGroup'
import { useAuthStore } from '@/store/authStore'

export function UsersPage() {
  const [users, setUsers] = useState<User[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [perPage] = useState(20)
  const [q, setQ] = useState('')
  const [type, setType] = useState<'all' | 'og' | 'client'>('all')
  const [loading, setLoading] = useState(false)
  const [statsData, setStatsData] = useState<{ total: number; active: number; recent: number; og_count: number; client_count: number } | null>(null)
  const [viewOnly, setViewOnly] = useState(false)

  const [sideOpen, setSideOpen] = useState(false)
  const [sideMounted, setSideMounted] = useState(false)
  const [sideVisible, setSideVisible] = useState(false)
  const [editingUser, setEditingUser] = useState<Partial<User> | null>(null)
  const currentUser = useAuthStore((s) => s.user)
  const isOG = (currentUser?.user_type || '').toLowerCase().includes('og') || (currentUser?.user_type || '').toLowerCase().includes('super')
  

  const badgeClassForType = (type?: string) => {
    const t = (type || '').toLowerCase()
    if (t.includes('og') || t.includes('super')) return 'bg-emerald-500/15 text-emerald-500 border-emerald-500 shadow-[0_0_12px_rgba(16,185,129,0.45)]'
    if (t.includes('client')) return 'bg-orange-500/15 text-orange-500 border-orange-500 shadow-[0_0_12px_rgba(249,115,22,0.45)]'
    return 'bg-muted/40 text-muted-foreground border-border'
  }


  const fetchUsers = async () => {
    setLoading(true)
    try {
      const resp = await usersApi.list({ page, perPage, q: q || undefined, type: type === 'all' ? undefined : type })
      setUsers(resp.users)
      setTotal(resp.total)
    } catch {
      setUsers([])
      setTotal(0)
    } finally {
      setLoading(false)
    }
  }

  const fetchStats = async () => {
    try {
      const s = await usersApi.stats()
      setStatsData(s)
    } catch {}
  }

  useEffect(() => {
    fetchUsers()
  }, [page, perPage, type, q])

  useEffect(() => {
    fetchStats()
  }, [])

  const stats = useMemo(() => ({
    total: statsData?.total ?? total,
    active: statsData?.active ?? users.filter((u) => !!u.last_login_at).length,
    recent: statsData?.recent ?? users.filter((u) => {
      if (!u.created_at) return false
      const created = new Date(u.created_at).getTime()
      const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
      return created >= sevenDaysAgo
    }).length,
    og: statsData?.og_count ?? users.filter((u) => (u.user_type || '').toLowerCase().includes('og')).length,
    client: statsData?.client_count ?? users.filter((u) => (u.user_type || '').toLowerCase().includes('client')).length
  }), [statsData, total, users])

  const openCreate = () => {
    setEditingUser({ user_type: 'client' })
    setViewOnly(false)
    setSideOpen(true)
  }

  const openEdit = (user: User) => {
    setEditingUser(user)
    setViewOnly(false)
    setSideOpen(true)
  }

  const openView = (user: User) => {
    setEditingUser(user)
    setViewOnly(true)
    setSideOpen(true)
  }

  useEffect(() => {
    if (sideOpen) {
      setSideMounted(true)
      setSideVisible(false)
      const t = setTimeout(() => setSideVisible(true), 0)
      return () => clearTimeout(t)
    }
    setSideVisible(false)
    const t = setTimeout(() => setSideMounted(false), 200)
    return () => clearTimeout(t)
  }, [sideOpen])

  useEffect(() => {
    if (!sideOpen) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setSideOpen(false)
        setEditingUser(null)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [sideOpen])

  const [confirmOpen, setConfirmOpen] = useState(false)
  const [confirmTarget, setConfirmTarget] = useState<User | null>(null)
  const askDelete = (user: User) => { setConfirmTarget(user); setConfirmOpen(true) }
  const confirmDelete = async () => {
    if (!confirmTarget) return
    try { await usersApi.delete(confirmTarget.id) } finally { setConfirmOpen(false); setConfirmTarget(null); fetchUsers() }
  }

  const handleSave = async () => {
    if (!editingUser) return
    const payload: any = {
      email: editingUser.email,
      name: editingUser.name,
      phone: editingUser.phone,
      avatar_url: editingUser.avatar_url,
      user_type_id: editingUser.user_type_id,
    }
    if (!payload.user_type_id && editingUser.user_type) {
      payload.user_type = editingUser.user_type
    }
    const editedId = editingUser.id
    try {
      if (editingUser.id) {
        const updated = await usersApi.update(editingUser.id, payload)
        if (currentUser && editedId && currentUser.id === editedId) {
          const { setUser } = useAuthStore.getState()
          setUser && setUser({ ...(currentUser as any), avatar_url: updated.avatar_url || payload.avatar_url })
        }
      } else {
        await usersApi.create(payload)
      }
    } catch {}
    setSideOpen(false)
    setEditingUser(null)
    fetchUsers()
  }

  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const [, setUploading] = useState(false)
  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 2 * 1024 * 1024) return
    setUploading(true)
    try {
      const form = new FormData()
      form.append('file', file)
      const data = await apiClient.post<{ url: string }>(
        '/api/v1/uploads/avatar',
        form,
        { headers: { 'Content-Type': 'multipart/form-data' } }
      )
      setEditingUser({ ...(editingUser || {}), avatar_url: data.url })
    } catch {}
    setUploading(false)
  }

  return (
    <div className="space-y-6 mt-[10px]">
      <PageHeader
        title="Usuários"
        subtitle="Gerencie contas e perfis"
        rightSlot={(
          <Button onClick={openCreate} variant="uiverse" className="px-3.5 py-1.5">
            <span className="inline-flex items-center gap-1">
              <Plus className="h-4 w-4" /> USUÁRIO
            </span>
          </Button>
        )}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        <div className="p-4 bg-card border border-border rounded-lg"><p className="text-sm text-muted-foreground">Total</p><p className="text-2xl font-bold">{stats.total}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg"><p className="text-sm text-muted-foreground">Ativos</p><p className="text-2xl font-bold">{stats.active}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg"><p className="text-sm text-muted-foreground">Novos (7d)</p><p className="text-2xl font-bold">{stats.recent}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg"><p className="text-sm text-muted-foreground">OG</p><p className="text-2xl font-bold">{stats.og}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg"><p className="text-sm text-muted-foreground">Clientes</p><p className="text-2xl font-bold">{stats.client}</p></div>
      </div>

      <div className="flex gap-3 items-center">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground"/>
          <Input
            value={q}
            onChange={(e) => {
              const val = e.target.value
              setQ(val)
              setPage(1)
            }}
            placeholder="Buscar por nome, email ou telefone"
            className="pl-9"
          />
        </div>
        <div className="flex items-center gap-2">
          <Filter className="h-4 w-4 text-muted-foreground"/>
          <select className="h-10 rounded-md border border-input bg-background px-3 text-sm" value={type} onChange={(e) => setType(e.target.value as any)}>
            <option value="all">Todos</option>
            <option value="og">OG</option>
            <option value="client">Cliente</option>
          </select>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {loading && <div className="text-muted-foreground">Carregando…</div>}
        {!loading && users.map((u) => (
          <div key={u.id} className="p-4 bg-card border border-border rounded-lg flex items-center justify-between cursor-pointer" onClick={() => { isOG ? openEdit(u) : openView(u) }}>
            <div className="flex items-center gap-2">
              <img src={u.avatar_url || `https://api.dicebear.com/7.x/initials/svg?seed=${encodeURIComponent(u.name || u.email || 'User')}`} alt="avatar" className="h-10 w-10 rounded-full border border-border object-cover"/>
              <div>
                <p className="text-foreground font-medium">{u.name}</p>
                {u.user_type && (
                  <div className="mt-[3px] mb-[3px]">
                    <span className={`px-2 py-0.5 text-[10px] rounded-md border ${badgeClassForType(u.user_type)}`}>
                      {(u.user_type || '').toUpperCase()}
                    </span>
                  </div>
                )}
                <p className="text-xs text-muted-foreground flex items-center gap-1 mt-[3px] mb-[3px]">
                  {u.email && (
                    <span className="inline-flex items-center gap-1"><Mail className="h-3 w-3" />{u.email}</span>
                  )}
                  {u.email && u.phone && <span className="mx-1">•</span>}
                  {u.phone && (
                    <span className="inline-flex items-center gap-1"><Phone className="h-3 w-3" />{u.phone}</span>
                  )}
                </p>
                {/* Oculto: badge de tipo de usuário */}
              </div>
            </div>
            <div className="relative" onClick={(e) => e.stopPropagation()}>
              <MenuActions onView={() => openView(u)} onEdit={() => openEdit(u)} onDelete={() => askDelete(u)} />
            </div>
          </div>
        ))}
      </div>

      {sideMounted && (
        <div className="fixed inset-0 z-40" data-helper>
          <div className={`absolute inset-0 bg-black/40 transition-opacity duration-200 ${sideVisible ? 'opacity-100' : 'opacity-0 pointer-events-none'}`} onClick={() => { setSideOpen(false); setEditingUser(null) }} />
          <div className={`absolute top-0 right-0 w-full sm:w-[420px] h-full bg-popover border-l border-border px-6 pb-6 pt-[7px] overflow-auto transition-transform duration-200 will-change-transform ${sideVisible ? 'translate-x-0' : 'translate-x-full'}`} data-helper>
            <div className="space-y-5 mt-0">
              <div className="flex items-center justify-between">
                <h2 className="text-xl font-semibold text-foreground">{viewOnly ? 'Detalhe do Usuário' : (editingUser?.id ? 'Editar Usuário' : 'Criar Usuário')}</h2>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Fechar"
                  className="absolute top-4 right-4"
                  onClick={() => { setSideOpen(false); setEditingUser(null) }}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
              <div className="flex flex-col items-center gap-2">
                <div className="relative">
                  <div
                    className={`h-24 w-24 rounded-full overflow-hidden border border-border bg-muted ${!viewOnly ? 'cursor-pointer' : ''}`}
                    onClick={!viewOnly ? () => fileInputRef.current?.click() : undefined}
                  >
                    {editingUser?.avatar_url ? (
                      <img src={editingUser.avatar_url} alt="Prévia do avatar" className="h-full w-full object-cover" />
                    ) : (
                      <img src={`https://api.dicebear.com/7.x/initials/svg?seed=${encodeURIComponent(editingUser?.name || editingUser?.email || 'User')}`} alt="Prévia do avatar" className="h-full w-full object-cover" />
                    )}
                  </div>
                  {!viewOnly && (
                    <button
                      type="button"
                      className="absolute -bottom-2 -right-2 h-8 w-8 rounded-full bg-primary text-primary-foreground border border-border shadow-lg flex items-center justify-center hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                      onClick={(e) => { e.stopPropagation(); fileInputRef.current?.click() }}
                    >
                      <Upload className="h-4 w-4" />
                    </button>
                  )}
                  <input ref={fileInputRef} type="file" accept="image/*" onChange={handleAvatarFile} className="hidden" />
                </div>
                <p className="text-sm text-foreground">Foto de Perfil</p>
                <p className="text-xs text-muted-foreground">JPG, PNG ou GIF (máx. 2MB)</p>
              </div>
              <div className="border-t border-border" />
              <div className="space-y-3">
                <div className="space-y-2">
                  <label className="text-sm text-foreground font-medium">Tipo de Usuário</label>
                  <select
                    className="flex h-10 w-full border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 rounded-[12px]"
                    value={(editingUser?.user_type || '').toLowerCase() || 'client'}
                    onChange={(e) => setEditingUser({ ...(editingUser||{}), user_type: e.target.value })}
                    disabled={viewOnly}
                  >
                    <option value="client">Cliente</option>
                    <option value="og">OG</option>
                  </select>
                </div>
                <div className="space-y-2">
                  <label className="text-sm text-foreground font-medium">Nome Completo</label>
                  <Input className="rounded-[12px]" value={editingUser?.name || ''} onChange={(e) => setEditingUser({ ...(editingUser||{}), name: e.target.value })} disabled={viewOnly}/>
                </div>
                <div className="space-y-2">
                  <label className="text-sm text-foreground font-medium">Email</label>
                  <Input className="rounded-[12px]" value={editingUser?.email || ''} onChange={(e) => setEditingUser({ ...(editingUser||{}), email: e.target.value })} disabled={viewOnly}/>
                </div>
                <div className="space-y-2">
                  <label className="text-sm text-foreground font-medium">Telefone</label>
                  {viewOnly ? (
                    <Input className="rounded-[12px]" value={editingUser?.phone || ''} disabled />
                  ) : (
                    <PhoneInputGroup
                      value={editingUser?.phone || ''}
                      onChange={(normalized) => setEditingUser({ ...(editingUser||{}), phone: normalized })}
                      className="rounded-[12px]"
                    />
                  )}
                </div>
                
                {/* Oculto: edição de tipo de usuário */}
                <div className="h-20" />
              </div>
            </div>
            {!viewOnly && (
              <Button
                onClick={handleSave}
                variant="uiverse"
                className="helper-fab absolute right-6 bottom-6 h-12 w-12 p-0 rounded-full shadow-lg"
                aria-label={editingUser?.id ? 'Salvar alterações' : 'Criar usuário'}
              >
                {editingUser?.id ? <Check className="h-6 w-6" /> : <Plus className="h-6 w-6" />}
              </Button>
            )}
          </div>
        </div>
      )}

      <ConfirmDialog open={confirmOpen} onCancel={() => { setConfirmOpen(false); setConfirmTarget(null) }} onConfirm={confirmDelete} />
    </div>
  )
}

function MenuActions({ onView, onEdit, onDelete }: { onView: () => void; onEdit: () => void; onDelete: () => void }) {
  const [open, setOpen] = useState(false)
  return (
    <div className="relative">
      <Button variant="ghost" size="icon" aria-label="Ações" onClick={() => setOpen((v) => !v)}>
        <MoreHorizontal className="h-4 w-4"/>
      </Button>
      {open && (
        <div className="absolute right-0 mt-2 w-36 rounded-md border border-border bg-popover shadow-sm z-10">
          <button className="w-full text-left px-3 py-2 text-sm hover:bg-accent" onClick={() => { setOpen(false); onView() }}><Eye className="inline h-4 w-4 mr-2"/> Visualizar</button>
          <button className="w-full text-left px-3 py-2 text-sm hover:bg-accent" onClick={() => { setOpen(false); onEdit() }}><Pencil className="inline h-4 w-4 mr-2"/> Editar</button>
          <button className="w-full text-left px-3 py-2 text-sm hover:bg-accent" onClick={() => { setOpen(false); onDelete() }}><Trash2 className="inline h-4 w-4 mr-2"/> Deletar</button>
        </div>
      )}
    </div>
  )
}

function ConfirmDialog({ open, onConfirm, onCancel }: { open: boolean; onConfirm: () => void; onCancel: () => void }) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50">
      <div className="absolute inset-0 bg-black/40" onClick={onCancel} />
      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[90%] max-w-sm rounded-lg border border-border bg-card p-6 shadow-lg">
        <h3 className="text-lg font-semibold text-foreground mb-2">Remover usuário?</h3>
        <p className="text-sm text-muted-foreground mb-4">Esta ação não pode ser desfeita. Deseja confirmar a remoção?</p>
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={onCancel}>Não</Button>
          <Button variant="destructive" onClick={onConfirm}>Sim, remover</Button>
        </div>
      </div>
    </div>
  )
}


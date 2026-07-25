import { useRef, useState } from 'react'
import { toast } from 'sonner'
import { invitationsApi, type InvitationDTO } from '../../lib/api/endpoints'
import { inviteText } from '../../lib/i18n/invitations'
import { Button } from '../../components/ui/Button'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// code-only-invites §"A tela mostra só o código" (era team-access-management 4.6).
//
// O produto NÃO envia e-mail (não-objetivo declarado): o CÓDIGO é distribuído
// pelo dono, por fora. Isso torna a cópia do código o passo crítico do fluxo —
// se ela falhar em silêncio, o convite existe no banco e ninguém nunca o recebe.
// Por isso a Clipboard API negada não vira erro: o código aparece num campo
// selecionável, com instrução de copiar à mão.
export function InviteDialog({
  onCreated,
  onClose,
}: {
  onCreated?: (invitation: InvitationDTO) => void
  onClose?: () => void
}) {
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<'view' | 'edit'>('view')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [criado, setCriado] = useState<InvitationDTO | null>(null)
  const [copiaCodigoManual, setCopiaCodigoManual] = useState(false)
  const codigoRef = useRef<HTMLInputElement>(null)

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    if (!EMAIL_RE.test(email.trim())) {
      setErro(inviteText.inviteInvalidEmail)
      return
    }

    setErro(null)
    setEnviando(true)
    try {
      const invitation = await invitationsApi.create({ email: email.trim(), role })
      setCriado(invitation)
      onCreated?.(invitation)
    } catch (e) {
      const resposta = (e as { response?: { status?: number; data?: { error?: string } } })?.response
      const codigo = resposta?.data?.error
      if (codigo === 'invitation_already_pending') setErro(inviteText.invitePending)
      else if (codigo === 'invalid_email') setErro(inviteText.inviteInvalidEmail)
      else if (resposta?.status === 403) setErro(inviteText.inviteForbidden)
      else setErro(inviteText.mutateFailure)
    } finally {
      setEnviando(false)
    }
  }

  async function copiarCodigo() {
    if (!criado?.short_code) return
    try {
      const clipboard = navigator.clipboard
      if (!clipboard?.writeText) throw new Error('sem clipboard')
      await clipboard.writeText(criado.short_code)
      setCopiaCodigoManual(false)
      toast.success(inviteText.codeCopied)
    } catch {
      setCopiaCodigoManual(true)
      codigoRef.current?.select()
      toast.warning(inviteText.copyCodeManual)
    }
  }

  if (criado) {
    return (
      <div role="dialog" aria-label={inviteText.inviteTitle} className="rounded-lg border p-4">
        <h3 className="font-medium">{inviteText.inviteCodeReady}</h3>
        <p className="mt-1 text-sm text-muted-foreground">{inviteText.inviteCodeHint}</p>

        {/* code-only-invites: o CÓDIGO é o único caminho. Fonte mono/tabular para
            não dançar de largura; o dono copia e passa para o convidado. */}
        {criado.short_code && (
          <>
            <input
              ref={codigoRef}
              aria-label={inviteText.inviteCodeReady}
              readOnly
              value={criado.short_code}
              onFocus={(e) => e.currentTarget.select()}
              className="mt-3 w-full rounded-md border bg-background px-3 py-2 text-center font-mono text-lg tracking-[0.3em] tabular-nums"
            />
            {copiaCodigoManual && <p className="mt-2 text-sm text-destructive">{inviteText.copyCodeManual}</p>}
          </>
        )}

        <div className="mt-4 flex gap-2">
          <Button type="button" onClick={copiarCodigo}>
            {inviteText.copyCode}
          </Button>
          <Button type="button" variant="outline" onClick={onClose}>
            {inviteText.close}
          </Button>
        </div>
      </div>
    )
  }

  return (
    <form role="dialog" aria-label={inviteText.inviteTitle} onSubmit={submit} className="rounded-lg border p-4">
      <h3 className="font-medium">{inviteText.inviteTitle}</h3>

      <label className="mt-3 block text-sm" htmlFor="convite-email">
        {inviteText.inviteEmailLabel}
      </label>
      {/* `type="text"` de propósito: com `type="email"` a validação nativa do
          navegador bloqueia o submit ANTES do nosso código e mostra um balão
          próprio, diferente em cada navegador e fora do `aria-live`. A validação
          é nossa, a mensagem é nossa, e o teclado certo vem do `inputMode`. */}
      <input
        id="convite-email"
        type="text"
        inputMode="email"
        autoComplete="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
      />

      <label className="mt-3 block text-sm" htmlFor="convite-papel">
        {inviteText.inviteRoleLabel}
      </label>
      <select
        id="convite-papel"
        value={role}
        onChange={(e) => setRole(e.target.value as 'view' | 'edit')}
        className="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm"
      >
        <option value="view">{inviteText.roleView}</option>
        <option value="edit">{inviteText.roleEdit}</option>
      </select>

      {erro && (
        <p role="alert" aria-live="polite" className="mt-2 text-sm text-destructive">
          {erro}
        </p>
      )}

      <div className="mt-4 flex gap-2">
        <Button type="submit" disabled={enviando}>
          {inviteText.inviteSubmit}
        </Button>
        <Button type="button" variant="outline" onClick={onClose}>
          {inviteText.close}
        </Button>
      </div>
    </form>
  )
}

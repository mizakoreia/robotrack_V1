import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Modal } from '@/components/ui/Modal'
import { Button } from '@/components/ui/Button'
import { useAuthStore } from '@/store/authStore'
import { consumeInviteByCode } from '@/lib/auth/session'
import { formatInviteCode, isCompleteInviteCode, normalizeInviteCode } from '@/lib/auth/code'
import { inviteText } from '@/lib/i18n/invitations'

// join-workspace-by-code — o diálogo de entrada por código para quem JÁ está
// autenticado. O buraco que ele fecha: um membro existente (ex.: o dono do demo)
// não passa pela tela de entrada, então não tinha onde aplicar um código sem
// deslogar. A porta vive no menu da conta (AppShell), sempre acessível — inclusive
// com um único workspace (o seletor de workspace só existe com mais de um).
//
// REUSO, não reimplementação: o aceite é `consumeInviteByCode`, o MESMO da tela de
// entrada, que já troca de workspace (`selectWorkspace`) e mapeia todos os erros em
// toast. Aqui só coletamos o código; o e-mail é o da SESSÃO (a invariante 6 exige
// e-mail do convite idêntico ao autenticado — um usuário logado só aceita convites
// para o próprio e-mail; não há grau de liberdade, então não há campo de e-mail).
export function JoinByCodeDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const navigate = useNavigate()
  const email = useAuthStore((s) => s.user?.email ?? '')
  const [codeInput, setCodeInput] = useState('')
  const [codeError, setCodeError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  // Cada abertura começa limpa: código anterior não sobra na próxima vez.
  useEffect(() => {
    if (open) {
      setCodeInput('')
      setCodeError(null)
      setBusy(false)
    }
  }, [open])

  if (!open) return null

  async function onSubmit(ev: React.FormEvent) {
    ev.preventDefault()
    if (!isCompleteInviteCode(codeInput)) {
      setCodeError(inviteText.codeInvalidFormat)
      return
    }
    setCodeError(null)
    setBusy(true)
    // `consumeInviteByCode` já: checa offline, chama o aceite autenticado, no
    // sucesso troca de workspace + toast, e em erro exibe o toast específico. Só
    // fechamos/navegamos quando entrou de fato; em erro o diálogo fica aberto com
    // o código, para corrigir sem redigitar tudo.
    const ok = await consumeInviteByCode(normalizeInviteCode(codeInput), email)
    if (ok) {
      onClose()
      navigate('/') // Visão Geral do workspace recém-ingressado
    } else {
      setBusy(false)
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={inviteText.joinByCodeTitle}>
      <form onSubmit={onSubmit} noValidate className="space-y-3" aria-label={inviteText.joinByCodeTitle}>
        <p className="text-sm text-text-muted">{inviteText.joinByCodeHint}</p>

        {/* Contexto somente-leitura: o e-mail da sessão é a identidade usada no
            aceite. Torna honesto o modo de falha "convite para outro e-mail". */}
        {email && (
          <p className="rounded-md border border-input bg-bg-main px-3 py-2 text-sm text-text-muted">
            {inviteText.joinByCodeAs(email)}
          </p>
        )}

        <div>
          <label htmlFor="join-code" className="block text-sm font-medium text-text-main">
            {inviteText.codeLabel}
          </label>
          <input
            id="join-code"
            type="text"
            inputMode="text"
            autoCapitalize="characters"
            autoCorrect="off"
            spellCheck={false}
            autoFocus
            maxLength={9} // 8 chars + 1 hífen
            aria-invalid={!!codeError}
            value={codeInput}
            onChange={(e) => setCodeInput(formatInviteCode(e.target.value))}
            placeholder={inviteText.codePlaceholder}
            className="mt-1 w-full rounded-md border border-input bg-bg-main px-3 py-2 font-mono tracking-[0.2em] tabular-nums text-text-main placeholder:tracking-normal placeholder:text-text-muted"
          />
        </div>

        <p aria-live="polite" className="min-h-[1.25rem] text-sm text-danger-ink">
          {codeError}
        </p>

        <div className="flex items-center justify-end gap-2">
          <Button type="button" variant="outline" size="sm" onClick={onClose}>
            {inviteText.close}
          </Button>
          <Button type="submit" size="sm" disabled={busy}>
            {busy ? inviteText.opening : inviteText.joinByCodeSubmit}
          </Button>
        </div>
      </form>
    </Modal>
  )
}

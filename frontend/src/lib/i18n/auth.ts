import { defineText } from './defineText'
import { authTextEn } from './auth.en'

// Módulo ÚNICO dos textos da tela de login/cadastro (identity-and-auth 5.1/5.2 /
// §3.1). Nenhum literal visível dessa tela vive fora daqui — é o primeiro momento
// que a pessoa lê no produto (rótulos, botões, e as mensagens de erro 422/409/401
// mapeadas ao campo certo). Espalhá-las deixaria uma dessincronizada das outras.
//
// A seção "Tenho um código de convite" continua lendo `inviteText` (invitations.ts)
// — só a validação inline do e-mail do convite mora aqui, por ser literal solto.
//
// internationalization G3 — `authText` é o eixo de idioma (pt-BR + en) sob o MESMO
// nome; o componente não muda de forma. O pt-BR canônico vive neste objeto (os
// sweeps o leem); o en em `auth.en.ts`. Glossário confirmado pelo dono:
// "Criar conta"→"Create account", "Entrar"→"Sign in", "E-mail"→"Email",
// "Senha"→"Password", "Enviando…"→"Sending…".
const authTextPtBR = {
  // Título / aria-label do formulário (alterna login ⇄ cadastro)
  createAccount: 'Criar conta',
  signIn: 'Entrar',
  ariaSignup: 'Cadastro',
  ariaLogin: 'Login',

  // Rótulos dos campos
  nameLabel: 'Nome',
  emailLabel: 'E-mail',
  passwordLabel: 'Senha',
  rememberMe: 'Manter conectado',

  // Ações
  sending: 'Enviando…',
  signInWithGoogle: 'Entrar com Google',
  haveAccountSignIn: 'Já tenho conta — Entrar',

  // Validação do cliente (espelha o servidor: senha ≥ 6, e-mail com formato)
  nameTooShort: 'Informe seu nome (mínimo 2 caracteres).',
  emailInvalid: 'Informe um e-mail válido.',
  passwordTooShort: (min: number) => `A senha precisa ter ao menos ${min} caracteres.`,

  // Erros do servidor mapeados ao campo (401/409/422) e fallbacks
  invalidCredentials: 'E-mail ou senha inválidos.',
  emailTaken: 'Este e-mail já está cadastrado.',
  checkData: 'Não foi possível concluir. Verifique os dados.',
  genericError: 'Algo deu errado. Tente novamente.',

  // Storage que não persiste (handshake §3.1)
  sessionWontPersist: 'Sua sessão não vai persistir neste navegador.',

  // Validação inline da entrada por código de convite (o restante vem de inviteText)
  codeEmailRequired: 'Informe o e-mail do convite.',
}

// internationalization G3 — SEM `as const`: o tipo alarga os literais para `string`
// e `en` pode ter outro texto. Os sweeps leem o TEXTO do arquivo, não o tipo — o
// canônico pt-BR segue estático e verificável. O idioma é resolvido no runtime.
export type AuthText = typeof authTextPtBR
export const authText: AuthText = defineText(authTextPtBR, authTextEn)

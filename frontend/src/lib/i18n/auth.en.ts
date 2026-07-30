import type { AuthText } from './auth'

// internationalization G3 — tradução EN (UK) dos textos de login/cadastro. Glossário
// confirmado pelo dono: "Criar conta" → "Create account", "Entrar" → "Sign in",
// "E-mail" → "Email", "Senha" → "Password", "Enviando…" → "Sending…".
export const authTextEn: AuthText = {
  createAccount: 'Create account',
  signIn: 'Sign in',
  ariaSignup: 'Sign up',
  ariaLogin: 'Sign in',

  nameLabel: 'Name',
  emailLabel: 'Email',
  passwordLabel: 'Password',
  rememberMe: 'Keep me signed in',

  sending: 'Sending…',
  signInWithGoogle: 'Sign in with Google',
  haveAccountSignIn: 'I already have an account — Sign in',

  nameTooShort: 'Enter your name (at least 2 characters).',
  emailInvalid: 'Enter a valid email.',
  passwordTooShort: (min: number) => `The password must be at least ${min} characters.`,

  invalidCredentials: 'Invalid email or password.',
  emailTaken: 'This email is already registered.',
  checkData: 'Could not complete. Please check your details.',
  genericError: 'Something went wrong. Please try again.',

  sessionWontPersist: 'Your session will not persist in this browser.',

  codeEmailRequired: 'Enter the invitation email.',
}

export interface LoginRequest {
  email: string
  password: string
}

export interface LoginResponse {
  access_token: string
  refresh_token: string
  user: {
    id: string
    email: string
    name: string
  }
}

export interface RefreshTokenResponse {
  access_token: string
}

export interface User {
  id: string
  email: string
  name: string
  phone?: string
  avatar_url?: string
  cpf_cnpj?: string
  cep?: string
  street?: string
  number?: string
  complement?: string
  district?: string
  city?: string
  state?: string
  user_type_id?: number
  user_type?: string
  last_login_at?: string
  login_count?: number
  created_at: string
  updated_at: string
  biography?: string
  biography_html?: string
  biography_text?: string
}

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

export interface Payment {
  id: string
  customer_id: string
  billing_type: 'BOLETO' | 'CREDIT_CARD' | 'PIX'
  value: number
  due_date: string
  status: 'PENDING' | 'RECEIVED' | 'CONFIRMED' | 'OVERDUE' | 'REFUNDED' | 'CHARGEBACK'
  invoice_url?: string
  pix_qr_code?: string
  pix_encoded_image?: string
  created_at: string
  updated_at: string
}

export interface CreatePaymentRequest {
  customer_id: string
  billing_type: 'BOLETO' | 'CREDIT_CARD' | 'PIX'
  value: number
  due_date: string
  description?: string
}

export interface WhatsappMessage {
  id: string
  message: string
  phone: string
  status: 'sent' | 'delivered' | 'read' | 'failed'
  created_at: string
}

export interface Sale {
  id: string | number
  customer_name?: string
  customer_email?: string
  amount: number
  currency: string
  status: string
  type: 'one_time' | 'subscription'
  method: 'pix' | 'credit_card'
  subscription_id?: string | number | null
  external_id?: string | null
  created_at?: string
}

export type ConnectionStatus = 'unknown' | 'connecting' | 'connected' | 'disconnected' | 'waiting_qr'

export interface ConnectionUpdateEvent {
  type: 'connection_update'
  instance_id: string
  status: ConnectionStatus | 'open' | 'close' | 'qr'
  data: {
    connection?: string
    qr?: string | null
    lastDisconnect?: { error?: string; code?: number } | null
    receivedPendingNotifications?: boolean
  }
  timestamp: string
}

export interface LogoutInstanceEvent {
  type: 'logout_instance'
  instance_id: string
  reason: string
  timestamp: string
}

export interface QrcodeUpdatedEvent {
  type: 'qrcode_updated'
  instance_id: string
  qr_code: string
  expires_in?: number
  session?: string
  timestamp: string
}

export type WhatsRealtimeEvent = ConnectionUpdateEvent | LogoutInstanceEvent | QrcodeUpdatedEvent

export interface Lead {
  id: number
  smart_id: string
  session_uuid: string
  source_type: string
  source_id: string
  current_stage: 'discovery' | 'enchantment' | 'closing'
  last_interaction_at?: string
  name?: string
  phone?: string
  ig_username?: string
  company_name?: string
  has_site?: boolean | null
  site_url?: string | null
  intention?: string | null
  product_category?: string | null
  is_categorized?: boolean
  last_message_content?: string | null
  last_message_type?: string | null
  last_message_sender_role?: 'user' | 'agent' | 'admin'
  discovery_level: number
  enchantment_level: number
  closing_level: number
  operation_key?: string | null
  stage_label?: string
  days_since_last_interaction?: number | null
  messages_count?: number
  has_unread?: boolean
  enchantment_criteria_questions?: Record<string, string>
  closing_criteria_questions?: Record<string, string>
  enchantment_criteria_count?: number
  closing_criteria_count?: number
  created_at?: string
}

export interface LeadMessage {
  id: number
  lead_id: number
  smart_id: string
  sender_role: 'user' | 'agent' | 'admin'
  content: string
  content_type: 'text' | 'image' | 'audio' | 'video' | 'file' | 'document'
  media_url?: string | null
  media_mime?: string | null
  created_at: string
}

export type PlanBillingKind = 'one_time' | 'subscription'

export interface PermissionLite {
  id: string
  key: string
  title?: string
  description?: string
}

export interface PlanFeature {
  id: string
  title: string
  identifier?: string
  is_active: boolean
  active?: boolean
  description_html?: string
  permission?: PermissionLite
  created_at?: string
  updated_at?: string
}

export interface Plan {
  id: string
  title: string
  identifier: string
  price: number
  billing_kind: PlanBillingKind
  is_active: boolean
  is_free: boolean
  is_popular: boolean
  active?: boolean
  free?: boolean
  popular?: boolean
  description_html?: string
  price_text_html?: string
  baseline_text_html?: string
  features?: PlanFeature[]
  created_at?: string
  updated_at?: string
}

import { apiClient, API_URL } from './client'
import type { User } from './types'

// Superfície de autenticação (identity-and-auth). O envelope de sucesso é
// `{ data: { access_token, user } }`; erros vêm em `error`/`errors` (mapeados
// pelo interceptor de erro no cliente). O Google é um REDIRECT de página inteira
// para o backend — não um endpoint XHR.
export interface AuthUserDTO {
  id: string
  name: string
  email: string
  avatar_url?: string | null
}

export interface AuthEnvelope {
  data: { access_token: string; user: AuthUserDTO }
}

export interface RegisterInput {
  name: string
  email: string
  password: string
  remember_me: boolean
}

export interface LoginInput {
  email: string
  password: string
  remember_me: boolean
}

export const authApi = {
  register: (data: RegisterInput) =>
    apiClient.postPublic<AuthEnvelope>('/auth/v1/registration', data),

  login: (data: LoginInput) =>
    apiClient.postPublic<AuthEnvelope>('/auth/v1/session', data),

  logout: () =>
    apiClient.delete('/auth/v1/session'),

  renew: () =>
    apiClient.post<AuthEnvelope>('/auth/v1/session/renew'),

  me: () =>
    apiClient.get<{ data: { user: AuthUserDTO } }>('/auth/v1/me'),

  // Edição de perfil é do template (fora do escopo de identity-and-auth, que
  // enxugou GET /auth/v1/me). Mantido para compat de ProfilePage.
  updateMe: (data: Record<string, unknown>) =>
    apiClient.patch<{ data: { user: AuthUserDTO } }>('/auth/v1/me', data),

  // Redirect de página inteira para o Google (D4.4). `remember_me` viaja em
  // omniauth.params e volta ao callback.
  googleRedirectUrl: (remember: boolean) =>
    `${API_URL}/users/auth/google_oauth2?remember_me=${remember ? 'true' : 'false'}`,

  // Aceite do convite — servido por `workspace-invitations`. Aqui o cliente só
  // repassa o token opaco capturado antes do login.
  acceptInvite: (token: string) =>
    apiClient.post(`/api/v1/invitations/${encodeURIComponent(token)}/accept`),
}

export const usersApi = {
  list: (params?: { page?: number; perPage?: number; q?: string; type?: 'og' | 'client' }) => {
    const page = params?.page ?? 1
    const perPage = params?.perPage ?? 20
    const q = params?.q ? `&q=${encodeURIComponent(params.q)}` : ''
    const type = params?.type ? `&type=${params.type}` : ''
    return apiClient.get<{ users: User[]; total: number }>(`/api/v1/users?page=${page}&per_page=${perPage}${q}${type}`)
  },
  
  get: (id: string) =>
    apiClient.get<User>(`/api/v1/users/${id}`),
  
  create: (data: Partial<User> & { user_type?: string }) =>
    apiClient.post<User>('/api/v1/users', data),
  
  update: (id: string, data: Partial<User> & { user_type?: string }) =>
    apiClient.patch<User>(`/api/v1/users/${id}`, data),
  
  delete: (id: string) =>
    apiClient.delete(`/api/v1/users/${id}`),

  stats: () =>
    apiClient.get<{ total: number; active: number; recent: number; og_count: number; client_count: number }>(`/api/v1/users/stats`),
}

export const countriesApi = {
  list: (q?: string) => apiClient.get<{ countries: { name: string; iso2: string; dial_code: string }[] }>(`/api/v1/countries${q ? `?q=${encodeURIComponent(q)}` : ''}`)
}

// workspace-core §"Índice do usuário" (workspace-tenancy 6.3). O papel vem no
// item apenas como rótulo — nunca é enviado de volta pelo cliente.
export interface WorkspaceItem {
  id: string
  name: string
  role: string
}

// workspace-invitations — superfície de convite e equipe.
//
// `preview` é a ÚNICA chamada pública (o token chega antes do login), por isso
// vai por `getPublic`: sem `Authorization`, e um 404 dela não é "sessão
// expirada". As demais são de domínio e levam `X-Workspace-Id` pelo interceptor.
export interface InvitationDTO {
  id: string
  email: string
  role: 'view' | 'edit'
  status: 'pending' | 'expired' | 'used'
  expires_at: string
  created_at: string
  invite_url: string
}

export interface InvitationPreviewDTO {
  workspace_name: string
  role: 'view' | 'edit'
  email_masked: string
  expires_at: string
  status: 'pending' | 'expired' | 'used'
}

export interface MemberDTO {
  id: string
  person_id: string | null
  name: string | null
  email: string | null
  role: 'owner' | 'edit' | 'view'
  is_owner: boolean
  invitation_id: string | null
}

export const invitationsApi = {
  list: () => apiClient.get<InvitationDTO[]>('/api/v1/invitations'),

  create: (data: { email: string; role: 'view' | 'edit' }) =>
    apiClient.post<InvitationDTO>('/api/v1/invitations', data),

  revoke: (id: string) => apiClient.delete(`/api/v1/invitations/${id}`),

  preview: (token: string) =>
    apiClient.getPublic<InvitationPreviewDTO>(`/api/v1/invitations/${encodeURIComponent(token)}`),

  // O aceite NÃO leva corpo: o papel vem do convite, e mandar `role` é 422
  // `unexpected_parameter` no servidor — de propósito, para a tentativa ficar
  // registrada em vez de ser ignorada.
  accept: (token: string) =>
    apiClient.post<{ workspace_id: string; role: 'view' | 'edit' }>(
      `/api/v1/invitations/${encodeURIComponent(token)}/accept`,
    ),
}

export const membershipsApi = {
  list: () => apiClient.get<MemberDTO[]>('/api/v1/memberships'),

  updateRole: (id: string, role: 'view' | 'edit') =>
    apiClient.patch<{ id: string; role: string }>(`/api/v1/memberships/${id}`, { role }),

  remove: (id: string) => apiClient.delete(`/api/v1/memberships/${id}`),
}

export const workspacesApi = {
  list: () => apiClient.get<WorkspaceItem[]>('/api/v1/workspaces'),
  updateName: (id: string, name: string) =>
    apiClient.patch<WorkspaceItem>(`/api/v1/workspaces/${id}`, { name }),
}

// commissioning-hierarchy 6.1 — hierarquia Projeto → Célula → Robô (§1.1).
//
// `id` vai no POST (D1): o cliente gera com `newId()` e o servidor honra, o que
// torna o replay idempotente (201 na primeira vez, 200 nas seguintes) e permite
// a atualização otimista usar o id definitivo desde o primeiro render.
// `lock_version` é obrigatório no PATCH (D-H9) — um 409 `stale_object` traz o
// recurso atual no corpo. `position` NÃO é editável item a item: ordem muda só
// por `reorder` em lote (§2.9).
export interface ProgressDTO {
  weighted: number
  done: number
  total: number
}

export interface RobotDTO {
  id: string
  cell_id: string
  name: string
  application: string
  position: number
  lock_version: number
  updated_at: string
  updated_by_person_id: string | null
  progress: ProgressDTO
  tasks: unknown[]
  tasks_count: number
}

export interface CellDTO {
  id: string
  project_id: string
  name: string
  position: number
  lock_version: number
  updated_at: string
  updated_by_person_id: string | null
  progress: ProgressDTO
  robots: RobotDTO[]
}

export interface ProjectDTO {
  id: string
  name: string
  position: number
  lock_version: number
  updated_at: string
  updated_by_person_id: string | null
  progress: ProgressDTO
  cells: CellDTO[]
}

// task-catalog 6.3 (§1.2, D-TC-3) — a lista de Aplicações NÃO é redeclarada em
// TS. O ponto de verdade é o backend (`Robot::APPLICATIONS`), servido por
// `GET /api/v1/meta/robot_applications` e consumido em runtime por
// `useRobotApplications` (`['meta','robotApplications']`, staleTime infinito). O
// tipo é um alias de string porque os valores só existem em runtime — um `grep`
// por `"Solda MIG"` em `frontend/src` fora de testes/fixtures deve dar zero.
export type RobotApplication = string

export const hierarchyApi = {
  listProjects: () => apiClient.get<ProjectDTO[]>('/api/v1/projects'),
  createProject: (data: { id: string; name: string }) =>
    apiClient.post<ProjectDTO>('/api/v1/projects', data),
  updateProject: (id: string, data: { name?: string; lock_version: number }) =>
    apiClient.patch<ProjectDTO>(`/api/v1/projects/${id}`, data),
  deleteProject: (id: string) => apiClient.delete(`/api/v1/projects/${id}`),
  reorderProjects: (scopeId: string, orderedIds: string[]) =>
    apiClient.patch<ProjectDTO[]>('/api/v1/projects/reorder', {
      scope_id: scopeId,
      ordered_ids: orderedIds,
    }),

  listCells: (projectId: string) =>
    apiClient.get<CellDTO[]>(`/api/v1/cells?project_id=${encodeURIComponent(projectId)}`),
  createCell: (data: { id: string; name: string; project_id: string }) =>
    apiClient.post<CellDTO>('/api/v1/cells', data),
  updateCell: (id: string, data: { name?: string; lock_version: number }) =>
    apiClient.patch<CellDTO>(`/api/v1/cells/${id}`, data),
  deleteCell: (id: string) => apiClient.delete(`/api/v1/cells/${id}`),
  reorderCells: (scopeId: string, orderedIds: string[]) =>
    apiClient.patch<CellDTO[]>('/api/v1/cells/reorder', {
      scope_id: scopeId,
      ordered_ids: orderedIds,
    }),

  listRobots: (cellId: string) =>
    apiClient.get<RobotDTO[]>(`/api/v1/robots?cell_id=${encodeURIComponent(cellId)}`),
  createRobot: (data: {
    id: string
    name: string
    cell_id: string
    application?: RobotApplication
  }) => apiClient.post<RobotDTO>('/api/v1/robots', data),
  updateRobot: (
    id: string,
    data: { name?: string; application?: RobotApplication; lock_version: number },
  ) => apiClient.patch<RobotDTO>(`/api/v1/robots/${id}`, data),
  deleteRobot: (id: string) => apiClient.delete(`/api/v1/robots/${id}`),
  reorderRobots: (scopeId: string, orderedIds: string[]) =>
    apiClient.patch<RobotDTO[]>('/api/v1/robots/reorder', {
      scope_id: scopeId,
      ordered_ids: orderedIds,
    }),

  // task-catalog 6.1 (§2.6, tarefa 5.4) — sincronização retroativa: aplica ao
  // robô os templates que faltam. O backend (G6, depende da tabela `tasks`)
  // responde a contagem de adicionadas. `appFilters` decide a aplicabilidade lá;
  // o cliente só dispara e invalida a lista de tarefas do robô.
  syncRobotTaskTemplates: (robotId: string) =>
    apiClient.post<SyncResultDTO>(
      `/api/v1/robots/${encodeURIComponent(robotId)}/sync_task_templates`,
    ),

  // robot-tasks 5.5 (§2.5) — criação de robôs em lote numa única requisição. O
  // servidor normaliza (trim, dedup, clamp 50) e materializa as tarefas-base
  // filtradas pela Aplicação. `id` por robô é uuid do cliente (D1).
  batchCreateRobots: (cellId: string, data: { application: string; robots: BatchRobotInput[] }) =>
    apiClient.post<BatchResultDTO>(
      `/api/v1/cells/${encodeURIComponent(cellId)}/robots/batch`,
      data,
    ),
}

export interface BatchRobotInput {
  id: string
  name: string
}

export interface BatchResultDTO {
  robots: { id: string; name: string; application: string; position: number }[]
  robot_count: number
  tasks_per_robot: number
}

// task-catalog 6.1 (§1.1, §3.9, §1.4 item 3, D-TC-5) — catálogo de tarefas-base.
//
// `appFilters` em camelCase, NUNCA `apps`: o nome legado morre na fronteira do
// backend, e o tipo TS não o expõe. `weight` chega inteiro quando integral
// (a entity serializa `1`, não `1.0`). O envio de escrita aceita `appFilters`
// (o coerce do backend também tolera `apps`, mas o cliente novo não o usa).
export interface TaskTemplateDTO {
  id: string
  cat: string
  desc: string
  weight: number
  appFilters: string[]
}

export interface TaskTemplateWriteInput {
  id?: string
  cat?: string
  desc?: string
  weight?: number
  appFilters?: string[]
}

// §2.6/5.3 — a resposta da sincronização conta as tarefas efetivamente
// inseridas, não o tamanho do conjunto aplicável. Campo `addedCount` (camelCase),
// como o endpoint responde (task-catalog TC-G6).
export interface SyncResultDTO {
  addedCount: number
}

export const taskTemplatesApi = {
  list: () => apiClient.get<TaskTemplateDTO[]>('/api/v1/task_templates'),

  create: (data: TaskTemplateWriteInput) =>
    apiClient.post<TaskTemplateDTO>('/api/v1/task_templates', data),

  update: (id: string, data: TaskTemplateWriteInput) =>
    apiClient.patch<TaskTemplateDTO>(`/api/v1/task_templates/${encodeURIComponent(id)}`, data),

  destroy: (id: string) =>
    apiClient.delete(`/api/v1/task_templates/${encodeURIComponent(id)}`),
}

// task-catalog 6.3 (§1.2) — metadados globais. Fonte única da lista de
// Aplicações; o frontend consome daqui em vez de manter uma segunda lista.
export const metaApi = {
  robotApplications: () =>
    apiClient.get<RobotApplication[]>('/api/v1/meta/robot_applications'),
}

// robot-tasks 4.2 (§3.5, §2.7, D-RT-6) — substituição do CONJUNTO de
// responsáveis. `person_ids` sempre por identidade, nunca nome. A resposta é o
// diff `{added, removed}` (arrays de person_id) — o que a UI e o tempo real
// consomem.
export interface AssigneeDiffDTO {
  added: string[]
  removed: string[]
}

export const taskAssigneesApi = {
  replace: (taskId: string, personIds: string[]) =>
    apiClient.put<AssigneeDiffDTO>(
      `/api/v1/tasks/${encodeURIComponent(taskId)}/assignees`,
      { person_ids: personIds },
    ),
}

// robot-tasks 4.4 — `PersonDTO` e o cadastro de pessoa. O backend `POST /people`
// é de `workspace-tenancy` (dependência declarada; ainda não entregue). Aqui só
// o fio do cliente que o modal de atribuição consome.
export interface PersonDTO {
  id: string
  name: string
}

export const peopleApi = {
  create: (data: { id: string; name: string }) =>
    apiClient.post<PersonDTO>('/api/v1/people', data),
}

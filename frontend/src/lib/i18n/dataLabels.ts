import { getLang } from './lang'

// internationalization G4 / D-I4 — MAPA DE EXIBIÇÃO dos VALORES de dado gravados em
// pt-BR no banco (enum `task_status`, `Robot::APPLICATIONS`, `task_templates.cat/desc`).
// A REGRA DE OURO: o dado NÃO é renomeado — estas funções só traduzem o RÓTULO na tela
// quando o idioma é en; em pt-BR devolvem o valor inalterado; um valor sem entrada no
// mapa (ex.: tarefa-base custom criada pelo usuário) cai no fallback e aparece como
// está (não se inventa tradução do texto do cliente). Chaves = grafia EXATA do banco,
// inclusive os erros legados preservados de propósito (`Traj, de Descarte`, `Robo`,
// `Automatico`, `ate`, `Trajetoria`) — a importação legada casa por `desc`.

// enum task_status
const STATUS_EN: Record<string, string> = {
  Pendente: 'Pending',
  'Em Andamento': 'In Progress',
  // decisão nº 3 do dono: "Done" na TELA (o relatório usa "Completed", resolvido no
  // servidor via en.report.yml — G5).
  Concluído: 'Done',
  'N/A': 'N/A',
}

// Robot::APPLICATIONS (CHECK de 6 literais)
const APPLICATION_EN: Record<string, string> = {
  'Misto / Geral': 'Mixed / General',
  'Solda Ponto': 'Spot Welding',
  'Solda MIG': 'MIG Welding',
  Handling: 'Handling',
  Sealing: 'Sealing',
  Outros: 'Others',
}

// 9 categorias (o prefixo A.–I. faz parte do valor e ordena por COLLATE "C" — mantido).
const CATEGORY_EN: Record<string, string> = {
  'A. Hardware': 'A. Hardware',
  'B. Rede': 'B. Network',
  'C. Segurança': 'C. Safety',
  'D. Processo': 'D. Process',
  'E. Trajetórias': 'E. Trajectories', // decisão nº 5: Trajectories (não Paths)
  'F. Interlocks': 'F. Interlocks',
  'G. Tryout': 'G. Tryout',
  'H. Otimização': 'H. Optimization',
  'I. Aceitação': 'I. Acceptance',
}

// 31 tarefas-base (default_catalog.rb) — grafia legada preservada nas CHAVES.
const BASE_TASK_EN: Record<string, string> = {
  // A. Hardware
  'Power On': 'Power On',
  'Mastering Check': 'Mastering Check',
  'Montagem de Ferramenta': 'Tool Mounting',
  'Check de Ferramenta/Umbilical': 'Tool/Umbilical Check',
  // B. Rede
  'Config. Endereço de IP': 'IP Address Config',
  'Rede Principal': 'Main Network',
  'Sub Rede': 'Subnet',
  // C. Segurança
  'Definir Cubos e esferas de segurança': 'Define Safety Cubes and Spheres',
  'Self Check de segurança do Robo': 'Robot Safety Self-Check',
  // D. Processo
  'TCP Check': 'TCP Check',
  'Calibração de Frame': 'Frame Calibration',
  Payload: 'Payload',
  'Calibração de Cola': 'Adhesive Calibration',
  'Check sinais de Gripper': 'Gripper Signals Check',
  // E. Trajetórias (Trajectory, não Path — decisão nº 5)
  'Carregar OLP': 'Load OLP',
  'Teach Traj. Sem Peça': 'Teach Trajectory — No Part',
  'Teach Traj. Com Peça': 'Teach Trajectory — With Part',
  'Carregar Parâmetros': 'Load Parameters',
  'Traj, de Descarte': 'Scrap Trajectory',
  Manutenção: 'Maintenance',
  // F. Interlocks
  'PLC-ROB interlocks/Sinais': 'PLC-Robot Interlocks/Signals',
  // G. Tryout
  'Dryrun Baixa velocidade ate 100%': 'Dry Run — Low Speed up to 100%',
  'Dryrun Diferentes velocidades': 'Dry Run — Various Speeds',
  'Automatico baixa velocidade': 'Automatic — Low Speed',
  'Speed up': 'Speed Up',
  // H. Otimização
  'Medição de Tempo de Ciclo Com peça': 'Cycle Time Measurement — With Part',
  'Otimização de Trajetoria': 'Trajectory Optimization',
  // I. Aceitação
  'Check de aceitação interna': 'Internal Acceptance Check',
  'Check de aceitação do cliente': 'Client Acceptance Check',
  'Treinamento ao cliente': 'Client Training',
  Acompanhamento: 'Follow-up',
}

function display(map: Record<string, string>, value: string | null | undefined): string {
  if (value == null) return ''
  if (getLang() !== 'en') return value
  return map[value] ?? value
}

/** Rótulo de status da tarefa (valor do enum pt-BR → EN de exibição). */
export const statusLabel = (v: string | null | undefined): string => display(STATUS_EN, v)
/** Rótulo da aplicação do robô (valor pt-BR → EN de exibição). */
export const applicationLabel = (v: string | null | undefined): string => display(APPLICATION_EN, v)
/** Rótulo da categoria de tarefa-base (prefixo A.–I. mantido). */
export const categoryLabel = (v: string | null | undefined): string => display(CATEGORY_EN, v)
/** Rótulo da descrição de tarefa-base do catálogo padrão; texto custom cai no fallback. */
export const baseTaskLabel = (v: string | null | undefined): string => display(BASE_TASK_EN, v)

import type { ReportText } from './report'

// internationalization G4 — tradução EN do chrome da tela de relatório.
// "Relatório" → "Report"; "Protocolo" → "Commissioning Protocol" (glossário do dono).
export const reportTextEn: ReportText = {
  title: 'Report',
  scopeLabel: 'Document scope',
  scopeAll: 'Entire workspace',
  print: 'Print',

  loading: 'Building the document…',

  offlineTitle: 'No connection',
  offlineBody:
    'Issuing the Commissioning Protocol requires a connection to the server — the document is not built from local data.',

  errorTitle: 'Could not issue the document',
  errorBody: 'The server failed during assembly. No partial section was shown.',
  retry: 'Try again',
}

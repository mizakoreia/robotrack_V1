// Utilitários de tema para gráficos
// Lê variáveis CSS do tema atual e fornece uma paleta de cores adequada ao modo dark/light
export function getThemeVars() {
  if (typeof window === 'undefined') {
    return {
      primary: '#8884d8',
      accent: '#82ca9d',
      fgMuted: '#9ca3af',
      grid: '#374151',
      primaryVibrant: '#8B5CF6',
      primaryVibrant2: '#A78BFA',
      accentVibrant: '#22D3EE'
    }
  }
  const styles = getComputedStyle(document.documentElement)
  const get = (name: string, fallback: string) => styles.getPropertyValue(name)?.trim() || fallback
  const normalizeColor = (val: string) => {
    const v = (val || '').trim()
    if (!v) return '#8884d8'
    if (v.startsWith('#') || v.startsWith('rgb') || v.startsWith('hsl')) return v
    if(/^\d+(\.\d+)?\s+\d+(\.\d+)?%\s+\d+(\.\d+)?%$/.test(v)) return `hsl(${v})`
    return v
  }
  return {
    primary: normalizeColor(get('--primary', '#8884d8')),
    accent: normalizeColor(get('--accent', '#82ca9d')),
    fgMuted: normalizeColor(get('--muted-foreground', '#9ca3af')),
    grid: normalizeColor(get('--border', '#374151')),
    primaryVibrant: '#8B5CF6',
    primaryVibrant2: '#A78BFA',
    accentVibrant: '#22D3EE'
  }
}

export function defaultPalette() {
  const { primary, accent } = getThemeVars()
  return [primary, accent, '#FFBB28', '#FF8042', '#AA66CC', '#33B5E5']
}

export function vibrantPalette() {
  return ['#60A5FA', '#F472B6', '#34D399', '#F59E0B', '#A78BFA', '#FB7185']
}

export const LEAD_SOURCE_ORDER = ['Chat', 'Facebook', 'Instagram', 'Site', 'WhatsApp']

export function leadSourceColor(name: string) {
  const palette = vibrantPalette()
  const idx = LEAD_SOURCE_ORDER.indexOf(name)
  return palette[idx >= 0 ? idx : 0]
}

import { afterEach, describe, expect, it } from 'vitest'
import { setLang, getLang, localeTag } from '../lang'
import { advanceText } from '../advances'
import { hierarchyText } from '../hierarchy'
import { progressText } from '../progress'
import { notificationPrefsText } from '../notifications'

// internationalization D-I2 — prova do EIXO DE IDIOMA. O default é pt-BR (as demais
// suítes rodam nele); aqui trocamos para en e voltamos, verificando que o MESMO
// export resolve o idioma corrente — string, função, plural, sub-objeto aninhado — e
// que a ENUMERAÇÃO segue devolvendo as chaves (o que os sweeps leem).
afterEach(() => setLang('pt-BR'))

describe('eixo de idioma (defineText)', () => {
  it('resolve string simples no idioma corrente', () => {
    setLang('pt-BR')
    expect(advanceText.title).toBe('Registrar avanço')
    setLang('en')
    expect(advanceText.title).toBe('Log progress') // decisão nº 1
  })

  it('resolve função de interpolação no idioma corrente', () => {
    setLang('en')
    expect(advanceText.statusChange('Done')).toBe('New status: Done')
  })

  it('resolve plural por idioma', () => {
    setLang('pt-BR')
    expect(hierarchyText.robotsBadge(1)).toBe('1 robô')
    expect(hierarchyText.robotsBadge(2)).toBe('2 robôs')
    setLang('en')
    expect(hierarchyText.robotsBadge(1)).toBe('1 robot')
    expect(hierarchyText.robotsBadge(2)).toBe('2 robots')
  })

  it('resolve sub-objeto aninhado no idioma corrente', () => {
    setLang('pt-BR')
    expect(progressText.metrics.raw_count.label).toBe('Progresso físico (tarefas concluídas)')
    setLang('en')
    expect(progressText.metrics.raw_count.label).toBe('Task completion') // decisão nº 4
    expect(progressText.metrics.weighted.label).toBe('Weighted progress')
  })

  it('resolve construtor com gênero/artigo por idioma', () => {
    setLang('en')
    expect(notificationPrefsText.trigger('robot', 'follow')).toBe('Robot notifications: following')
  })

  it('a enumeração usa as chaves pt-BR (o que os sweeps leem) mesmo em en', () => {
    setLang('en')
    // Object.keys/values continua enumerando a forma (chaves), não some no Proxy.
    expect(Object.keys(advanceText)).toContain('title')
    expect(Object.values(advanceText).length).toBeGreaterThan(5)
  })

  it('localeTag acompanha o idioma (Intl/datas)', () => {
    setLang('pt-BR')
    expect(localeTag()).toBe('pt-BR')
    setLang('en')
    expect(localeTag()).toBe('en-GB')
    expect(getLang()).toBe('en')
  })
})

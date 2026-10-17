import { describe, expect, it } from 'vitest'
import { PROFILES, costPerUse, profileOf } from '../value'
import { API_MODELS, PLANS, PROVIDERS } from '../../data/pricing'
import { PERSONAS } from '../../data/personas'

const model = (id: string) => API_MODELS.find((m) => m.id === id)!

describe('价格目录', () => {
  it('每条价格都有官网来源和核对日期', () => {
    for (const x of [...PLANS, ...API_MODELS]) {
      expect(x.source, x.id).toMatch(/^https:\/\//)
      expect(x.checked, x.id).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    }
  })
  it('id 不重复，服务商都存在', () => {
    const ids = [...PLANS, ...API_MODELS].map((x) => x.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const x of [...PLANS, ...API_MODELS]) expect(PROVIDERS.some((p) => p.key === x.provider), x.id).toBe(true)
  })
  it('DeepSeek 没有会员套餐', () => {
    expect(PROVIDERS.find((p) => p.key === 'deepseek')!.hasSubscription).toBe(false)
    expect(PLANS.some((p) => p.provider === 'deepseek')).toBe(false)
  })
  it('缓存价不高于标准输入价', () => {
    for (const m of API_MODELS) expect(m.cachedInput ?? m.input, m.id).toBeLessThanOrEqual(m.input)
  })
})

describe('用量估算', () => {
  it('Agent 画像和 Anthropic 官方数据对得上（每工作日约 $13，月 $150–250）', () => {
    const agent = profileOf('agent')
    const persona = PERSONAS.find((p) => p.key === 'agent')!
    // 用 Sonnet / Opus 两档，月花费应该覆盖官方区间
    const sonnet = costPerUse(agent, model('claude-sonnet-5.5')) * persona.usesPerMonth
    const opus = costPerUse(agent, model('claude-opus-5.5')) * persona.usesPerMonth
    expect(sonnet).toBeLessThan(250)
    expect(opus).toBeGreaterThan(150)
    expect(opus).toBeLessThan(400)
  })
  it('日常问答一次很便宜（DeepSeek Flash 不到 1 分钱）', () => {
    expect(costPerUse(profileOf('chat'), model('deepseek-flash'))).toBeLessThan(0.01)
  })
  it('强度越高单次越贵', () => {
    const m = model('claude-sonnet-5.5')
    const costs = PROFILES.map((p) => costPerUse(p, m))
    for (let i = 1; i < costs.length; i++) expect(costs[i]).toBeGreaterThan(costs[i - 1])
  })
})

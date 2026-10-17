// 宣传片里写死的数字必须和 App 实际算出来的一致
import { expect, it } from 'vitest'
import { costPerUse, profileOf } from '../value'
import { API_MODELS, PLANS } from '../../data/pricing'
import { toCNY } from '../../db'

it('宣传片比价数字', () => {
  const rate = 7.1
  const uses = 180
  const agent = profileOf('agent')
  const opus = API_MODELS.find((m) => m.id === 'claude-opus-5.5')!
  const opusMonthly = toCNY(costPerUse(agent, opus), 'USD', rate) * uses
  const max5 = toCNY(PLANS.find((p) => p.id === 'claude-max5')!.price, 'USD', rate)
  const glm = PLANS.find((p) => p.id === 'glm-lite')!.price
  console.log({ opusMonthly: Math.round(opusMonthly), max5: Math.round(max5), glm, saving: Math.round(opusMonthly - max5) })
  expect(Math.round(max5)).toBe(710)
  expect(glm).toBe(118)
  expect(Math.round(opusMonthly)).toBe(1799)
  expect(Math.round(opusMonthly - max5)).toBe(1089)
})

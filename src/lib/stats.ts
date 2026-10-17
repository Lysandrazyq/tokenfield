import { type Account, type Settings, toCNY } from '../db'
import { presetOf } from '../presets'

export interface SpendSlice {
  account: Account
  cny: number
  color: string
}

export function monthlySpend(accounts: Account[], settings: Settings) {
  const slices: SpendSlice[] = accounts
    .map((a) => ({ account: a, cny: toCNY(a.monthlyCost || 0, a.currency, settings.usdRate), color: presetOf(a.provider).color }))
    .sort((x, y) => y.cny - x.cny)
  const total = slices.reduce((s, x) => s + x.cny, 0)
  return { total, slices }
}

export function formatCNY(n: number) {
  return `¥${n.toLocaleString('zh-CN', { maximumFractionDigits: n >= 100 ? 0 : 2 })}`
}

export function formatMoney(n: number, currency: 'CNY' | 'USD') {
  return currency === 'USD' ? `$${n.toLocaleString('en-US', { maximumFractionDigits: 2 })}` : formatCNY(n)
}

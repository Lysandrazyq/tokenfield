import type { Billing } from './db'
import { PROVIDERS, providerOf } from './data/pricing'

/** 兼容旧代码：预设就是服务商目录 */
export const PRESETS = PROVIDERS.map((p) => ({ key: p.key, name: p.name, billing: p.defaultBilling, currency: p.currency, color: p.color }))
export const presetOf = (key: string) => {
  const p = providerOf(key)
  return { key: p.key, name: p.name, billing: p.defaultBilling, currency: p.currency, color: p.color }
}

export const BILLING_LABEL: Record<Billing, string> = {
  subscription: '会员订阅',
  payg: '按量付费',
  balance: '中转站余额',
}

export const COST_LABEL: Record<Billing, string> = {
  subscription: '月费',
  payg: '本月预计花费',
  balance: '本月充值',
}

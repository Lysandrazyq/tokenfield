import Dexie, { type EntityTable } from 'dexie'

export type Billing = 'subscription' | 'payg' | 'balance'
export type Currency = 'CNY' | 'USD'
export type ResetKind = 'none' | 'hours' | 'weekly' | 'monthly'

export interface Account {
  id?: number
  name: string
  provider: string
  billing: Billing
  /** 订阅：月费；按量：本月预计花费；中转站：本月充值 */
  monthlyCost: number
  currency: Currency
  /** 订阅的下次续费时间（ISO），过期后自动按月顺延 */
  renewAt?: string
  /** 中转站当前余额 */
  balance?: number
  resetKind: ResetKind
  resetHours?: number
  /** 某一次已知的重置时间点（ISO），用于推算后续重置 */
  resetAnchor?: string
  notifyReset: boolean
  models: string
  note: string
  createdAt: string
  /** 选的官方套餐（pricing.ts 里的 Plan.id），用于显示限制、比价 */
  planId?: string
  /** 按量付费时主要用的模型（ApiModel.id），用于估算 */
  modelId?: string
}

/** 使用记录：一天一条，记这天用了多少次、多重。只订一个会员时，靠它判断值不值 */
export type Intensity = 'chat' | 'write' | 'code' | 'agent'

export interface Usage {
  id?: number
  accountId: number
  /** YYYY-MM-DD */
  day: string
  /** 这天的使用次数（一次 = 一轮对话 / 一个任务） */
  count: number
  intensity: Intensity
  /** 碰到额度上限了 */
  hitLimit?: boolean
}

export interface Expiry {
  id?: number
  title: string
  accountId?: number
  expiresAt: string
  done: boolean
}

export interface Settings {
  id: 'main'
  usdRate: number
  remindHours: number
  handle: string
}

export const DEFAULT_SETTINGS: Settings = { id: 'main', usdRate: 7.1, remindHours: 24, handle: '' }

export const db = new Dexie('ai-quota-keeper') as Dexie & {
  accounts: EntityTable<Account, 'id'>
  expiries: EntityTable<Expiry, 'id'>
  settings: EntityTable<Settings, 'id'>
  usage: EntityTable<Usage, 'id'>
}

db.version(1).stores({
  accounts: '++id, provider',
  expiries: '++id, accountId, expiresAt',
  settings: 'id',
})

db.version(2).stores({
  usage: '++id, accountId, day, [accountId+day]',
})

export async function getSettings(): Promise<Settings> {
  return { ...DEFAULT_SETTINGS, ...(await db.settings.get('main')) }
}

export function toCNY(amount: number, currency: Currency, usdRate: number) {
  return currency === 'USD' ? amount * usdRate : amount
}

export async function exportData() {
  return {
    app: 'ai-quota-keeper',
    version: 2,
    exportedAt: new Date().toISOString(),
    accounts: await db.accounts.toArray(),
    expiries: await db.expiries.toArray(),
    usage: await db.usage.toArray(),
    settings: await getSettings(),
  }
}

export async function importData(data: Awaited<ReturnType<typeof exportData>>) {
  if (data?.app !== 'ai-quota-keeper') throw new Error('不是额度终端的备份文件')
  await db.transaction('rw', [db.accounts, db.expiries, db.settings, db.usage], async () => {
    await Promise.all([db.accounts.clear(), db.expiries.clear(), db.usage.clear()])
    await db.accounts.bulkAdd(data.accounts)
    await db.expiries.bulkAdd(data.expiries)
    // 旧版备份没有 usage
    if (data.usage?.length) await db.usage.bulkAdd(data.usage)
    await db.settings.put({ ...data.settings, id: 'main' })
  })
}

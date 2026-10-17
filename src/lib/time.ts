import dayjs from 'dayjs'
import type { Account, Expiry } from '../db'

export type EventKind = 'expiry' | 'renew' | 'reset'

export interface TimelineEvent {
  key: string
  kind: EventKind
  at: dayjs.Dayjs
  title: string
  accountId?: number
  expiryId?: number
  /** 是否需要推送提醒 */
  notify: boolean
}

/** 把一个过去的时间点按固定周期往后推，直到晚于 now */
function rollForward(start: dayjs.Dayjs, step: (d: dayjs.Dayjs) => dayjs.Dayjs, now: dayjs.Dayjs) {
  let t = start
  // 上限保护，避免锚点填得太早时死循环
  for (let i = 0; i < 100000 && !t.isAfter(now); i++) t = step(t)
  return t
}

export function nextRenewal(a: Account, now = dayjs()) {
  if (a.billing !== 'subscription' || !a.renewAt) return null
  return rollForward(dayjs(a.renewAt), (d) => d.add(1, 'month'), now)
}

export function nextReset(a: Account, now = dayjs()) {
  if (a.resetKind === 'none' || !a.resetAnchor) return null
  const anchor = dayjs(a.resetAnchor)
  switch (a.resetKind) {
    case 'hours': {
      const h = a.resetHours && a.resetHours > 0 ? a.resetHours : 5
      if (anchor.isAfter(now)) return anchor
      const periods = Math.floor(now.diff(anchor, 'minute') / (h * 60)) + 1
      return anchor.add(periods * h, 'hour')
    }
    case 'weekly':
      return rollForward(anchor, (d) => d.add(1, 'week'), now)
    case 'monthly':
      return rollForward(anchor, (d) => d.add(1, 'month'), now)
  }
}

export function buildTimeline(accounts: Account[], expiries: Expiry[], now = dayjs()): TimelineEvent[] {
  const events: TimelineEvent[] = []
  const nameOf = new Map(accounts.map((a) => [a.id, a.name]))
  for (const a of accounts) {
    const renew = nextRenewal(a, now)
    if (renew) events.push({ key: `renew-${a.id}`, kind: 'renew', at: renew, title: `${a.name} 续费`, accountId: a.id, notify: true })
    const reset = nextReset(a, now)
    if (reset) events.push({ key: `reset-${a.id}`, kind: 'reset', at: reset, title: `${a.name} 额度重置`, accountId: a.id, notify: a.notifyReset })
  }
  for (const e of expiries) {
    if (e.done) continue
    const owner = e.accountId != null ? nameOf.get(e.accountId) : undefined
    events.push({
      key: `expiry-${e.id}`,
      kind: 'expiry',
      at: dayjs(e.expiresAt),
      title: owner ? `${owner} · ${e.title}` : e.title,
      accountId: e.accountId,
      expiryId: e.id,
      notify: true,
    })
  }
  return events.sort((x, y) => x.at.valueOf() - y.at.valueOf())
}

export function countdown(target: dayjs.Dayjs, now = dayjs()) {
  const mins = target.diff(now, 'minute')
  if (mins < 0) return '已过期'
  if (mins < 60) return `${mins} 分钟`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours} 时 ${mins % 60} 分`
  const days = Math.floor(hours / 24)
  return `${days} 天 ${hours % 24} 时`
}

/** 给 <input type="datetime-local"> 用的本地时间字符串 */
export function toLocalInput(iso?: string) {
  return iso ? dayjs(iso).format('YYYY-MM-DDTHH:mm') : ''
}

export function fromLocalInput(v: string) {
  return v ? dayjs(v).toISOString() : undefined
}

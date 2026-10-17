import dayjs from 'dayjs'
import { Capacitor } from '@capacitor/core'
import { LocalNotifications } from '@capacitor/local-notifications'
import type { Account, Expiry, Settings } from '../db'
import { buildTimeline, nextReset, type TimelineEvent } from './time'

export const isNative = Capacitor.isNativePlatform()

interface Reminder {
  key: string
  at: dayjs.Dayjs
  title: string
  body: string
}

/** 提醒最多排到多少天以后（安卓有待发通知数量上限，不需要排太远） */
const HORIZON_DAYS = 45
/** 按小时重置的账号，最多提前排几次 */
const MAX_RESETS_PER_ACCOUNT = 12

function eventBody(e: TimelineEvent) {
  const when = e.at.format('M月D日 HH:mm')
  if (e.kind === 'reset') return '额度已经重置，可以继续用了'
  if (e.kind === 'renew') return `将于 ${when} 自动续费，不想续记得取消`
  return `将于 ${when} 到期，别浪费了`
}

export function buildReminders(accounts: Account[], expiries: Expiry[], settings: Settings, now = dayjs()): Reminder[] {
  const horizon = now.add(HORIZON_DAYS, 'day')
  const reminders: Reminder[] = []
  for (const e of buildTimeline(accounts, expiries, now)) {
    if (!e.notify || !e.at.isAfter(now) || e.at.isAfter(horizon)) continue
    if (e.kind === 'reset') {
      // 重置是周期性的，往后多排几次，App 不打开也能持续提醒
      const a = accounts.find((x) => x.id === e.accountId)!
      let t: dayjs.Dayjs | null = e.at
      for (let i = 0; t && i < MAX_RESETS_PER_ACCOUNT && !t.isAfter(horizon); i++) {
        reminders.push({ key: `${e.key}-${t.valueOf()}`, at: t, title: e.title, body: eventBody(e) })
        t = nextReset(a, t)
      }
      continue
    }
    // 续费和到期提前提醒；如果已经在提醒窗口内，就尽快提醒一次
    let at = e.at.subtract(settings.remindHours, 'hour')
    if (!at.isAfter(now)) at = now.add(10, 'second')
    reminders.push({ key: `${e.key}-${e.at.valueOf()}`, at, title: `⏰ ${e.title}`, body: eventBody(e) })
  }
  return reminders
}

/** 把字符串 key 映射成安卓通知需要的正整数 id */
function idOf(key: string) {
  let h = 0
  for (let i = 0; i < key.length; i++) h = (Math.imul(31, h) + key.charCodeAt(i)) | 0
  return Math.abs(h) || 1
}

const FIRED_KEY = 'fired-reminders'

function loadFired(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(FIRED_KEY) ?? '[]'))
  } catch {
    return new Set()
  }
}

function markFired(key: string) {
  const f = loadFired()
  f.add(key)
  localStorage.setItem(FIRED_KEY, JSON.stringify([...f].slice(-200)))
}

let webTimers: number[] = []

export async function ensurePermission() {
  if (isNative) {
    const { display } = await LocalNotifications.requestPermissions()
    return display === 'granted'
  }
  if (!('Notification' in window)) return false
  if (Notification.permission === 'default') await Notification.requestPermission()
  return Notification.permission === 'granted'
}

export async function permissionGranted() {
  if (isNative) return (await LocalNotifications.checkPermissions()).display === 'granted'
  return 'Notification' in window && Notification.permission === 'granted'
}

/** 数据变化后整体重排一遍提醒：先清空，再按最新数据排 */
export async function scheduleAll(accounts: Account[], expiries: Expiry[], settings: Settings) {
  const fired = loadFired()
  const reminders = buildReminders(accounts, expiries, settings).filter((r) => !fired.has(r.key))

  if (isNative) {
    if (!(await permissionGranted())) return
    const pending = await LocalNotifications.getPending()
    if (pending.notifications.length) await LocalNotifications.cancel({ notifications: pending.notifications.map((n) => ({ id: n.id })) })
    if (!reminders.length) return
    // 马上就要弹的提醒记为已发，避免每次打开 App 重复弹
    const soon = dayjs().add(1, 'minute')
    reminders.filter((r) => !r.at.isAfter(soon)).forEach((r) => markFired(r.key))
    await LocalNotifications.schedule({
      notifications: reminders.slice(0, 60).map((r) => ({
        id: idOf(r.key),
        title: r.title,
        body: r.body,
        schedule: { at: r.at.toDate(), allowWhileIdle: true },
      })),
    })
    return
  }

  // 网页没有后台，只能在页面开着的时候提醒 24 小时内的事项
  webTimers.forEach(clearTimeout)
  webTimers = []
  if (!(await permissionGranted())) return
  const now = dayjs()
  for (const r of reminders) {
    const delay = r.at.diff(now)
    if (delay > 24 * 3600 * 1000) continue
    webTimers.push(
      window.setTimeout(() => {
        new Notification(r.title, { body: r.body, icon: '/icon.svg' })
        markFired(r.key)
      }, Math.max(delay, 0)),
    )
  }
}

import { useSyncExternalStore } from 'react'
import { liveQuery } from 'dexie'
import { db, DEFAULT_SETTINGS, type Account, type Expiry, type Settings, type Usage } from '../db'

/**
 * 全站共用的数据快照。
 *
 * 之前每个页面各自 useLiveQuery，IndexedDB 是异步的：页面第一帧总是空的，下一帧才有内容。
 * 切页时 View Transition 恰好拍到那一帧空白 → 闪一下。
 * 现在启动时先把数据读进内存（main.tsx 等它读完才渲染），之后各页同步读快照，永远不会有空帧；
 * 数据库有改动时 liveQuery 推送新快照。
 */

export interface Snapshot {
  accounts: Account[]
  expiries: Expiry[]
  usage: Usage[]
  settings: Settings
}

let snap: Snapshot = { accounts: [], expiries: [], usage: [], settings: DEFAULT_SETTINGS }
const listeners = new Set<() => void>()

async function readAll(): Promise<Snapshot> {
  const [accounts, expiries, usage, settings] = await Promise.all([
    db.accounts.toArray(),
    db.expiries.toArray(),
    db.usage.toArray(),
    db.settings.get('main'),
  ])
  return { accounts, expiries, usage, settings: { ...DEFAULT_SETTINGS, ...settings } }
}

/** 启动时同步拿到完整数据再渲染；之后的改动由 liveQuery 推送 */
export async function preload() {
  try {
    snap = await readAll()
  } catch (e) {
    console.error(e)
  }
  liveQuery(readAll).subscribe({
    next: (v) => {
      snap = v
      listeners.forEach((l) => l())
    },
    error: (e) => console.error(e),
  })
}

const subscribe = (l: () => void) => {
  listeners.add(l)
  return () => listeners.delete(l)
}

export function useStore() {
  return useSyncExternalStore(subscribe, () => snap)
}

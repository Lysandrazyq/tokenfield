import { useEffect, useState } from 'react'
import { useParams, useSearchParams } from 'react-router-dom'
import dayjs from 'dayjs'
import { useStore } from '../lib/store'
import { db, type Expiry } from '../db'
import { fromLocalInput, toLocalInput } from '../lib/time'
import { Field, PageHeader, Toggle } from '../components/ui'
import { useGo } from '../lib/useGo'

const QUICK = ['完全重置券', '免费试用到期', '中转站额度到期', '活动赠送额度']

export default function ExpiryEdit() {
  const { id } = useParams()
  const [params] = useSearchParams()
  const isNew = id === 'new'
  const { back } = useGo()
  const { accounts, expiries } = useStore()
  const [e, setE] = useState<Expiry | null>(
    isNew
      ? {
          title: '完全重置券',
          accountId: params.get('account') ? Number(params.get('account')) : undefined,
          expiresAt: dayjs().add(7, 'day').hour(23).minute(59).second(0).toISOString(),
          done: false,
        }
      : (expiries.find((x) => x.id === Number(id)) ?? null),
  )

  useEffect(() => {
    if (!isNew && !e) back('/')
  }, [isNew, e, back])

  if (!e) return null
  const set = (patch: Partial<Expiry>) => setE({ ...e, ...patch })

  const save = async (ev: React.FormEvent) => {
    ev.preventDefault()
    const clean = { ...e, title: e.title.trim() || '到期项' }
    if (isNew) await db.expiries.add(clean)
    else await db.expiries.put(clean)
    back('/')
  }

  const remove = async () => {
    if (!confirm(`删除「${e.title}」？`)) return
    await db.expiries.delete(e.id!)
    back('/')
  }

  return (
    <form onSubmit={save} className="space-y-5">
      <PageHeader title={isNew ? '添加到期项' : '编辑到期项'} subtitle="重置券、试用期、赠送额度，到期前提醒你用掉" />

      <div className="card space-y-4">
        <Field label="名称">
          <input className="input" value={e.title} onChange={(ev) => set({ title: ev.target.value })} />
        </Field>
        <div className="flex flex-wrap gap-2">
          {QUICK.map((q) => (
            <button
              key={q}
              type="button"
              onClick={() => set({ title: q })}
              aria-pressed={e.title === q}
              className="chip"
            >
              {q}
            </button>
          ))}
        </div>
        <Field label="属于哪个 AI（选填）">
          <select
            className="input"
            value={e.accountId ?? ''}
            onChange={(ev) => set({ accountId: ev.target.value ? Number(ev.target.value) : undefined })}
          >
            <option value="">不关联</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </Field>
        <Field label="到期时间">
          <input className="input" type="datetime-local" value={toLocalInput(e.expiresAt)} onChange={(ev) => set({ expiresAt: fromLocalInput(ev.target.value) ?? e.expiresAt })} />
        </Field>
        {!isNew && (
          <div className="-mx-4 -mb-4">
            <Toggle label="已经用掉了" checked={e.done} onChange={(done) => set({ done })} />
          </div>
        )}
      </div>

      <div className="flex gap-3">
        {!isNew && (
          <button type="button" onClick={remove} className="btn-danger">
            删除
          </button>
        )}
        <button type="submit" className="btn-primary flex-1">
          保存
        </button>
      </div>
    </form>
  )
}

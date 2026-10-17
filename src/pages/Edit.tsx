import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import dayjs from 'dayjs'
import { db, type Account, type ResetKind } from '../db'
import { useStore } from '../lib/store'
import { BILLING_LABEL, COST_LABEL } from '../presets'
import { PROVIDERS, providerOf, plansOf, modelsOf, API_MODELS } from '../data/pricing'
import { fromLocalInput, toLocalInput } from '../lib/time'
import { useGo } from '../lib/useGo'
import { Field, PageHeader, Segmented, Toggle } from '../components/ui'
import ProviderBadge from '../components/ProviderBadge'

function blank(): Account {
  const p = providerOf('chatgpt')
  const plan = plansOf('chatgpt').find((x) => x.id === 'chatgpt-plus')
  return {
    name: p.name,
    provider: p.key,
    billing: p.defaultBilling,
    planId: plan?.id,
    modelId: modelsOf('chatgpt').find((m) => m.tier === 'balanced')?.id,
    monthlyCost: plan?.price ?? 0,
    currency: p.currency,
    renewAt: dayjs().add(1, 'month').startOf('day').toISOString(),
    resetKind: 'none',
    resetHours: 5,
    notifyReset: false,
    models: '',
    note: '',
    createdAt: new Date().toISOString(),
  }
}

const RESET_OPTIONS: { value: ResetKind; label: string }[] = [
  { value: 'none', label: '不重置' },
  { value: 'hours', label: '按小时' },
  { value: 'weekly', label: '每周' },
  { value: 'monthly', label: '每月' },
]

export default function Edit() {
  const { id } = useParams()
  const isNew = id === 'new'
  const { back } = useGo()
  const { accounts } = useStore()
  const [a, setA] = useState<Account | null>(() => (isNew ? blank() : (accounts.find((x) => x.id === Number(id)) ?? null)))

  useEffect(() => {
    if (!isNew && !a) back('/')
  }, [isNew, a, back])

  if (!a) return null
  const set = (patch: Partial<Account>) => setA({ ...a, ...patch })
  const provider = providerOf(a.provider)
  const plans = plansOf(a.provider)
  const models = modelsOf(a.provider)
  const plan = plans.find((p) => p.id === a.planId)
  // 没有本家 API 价格时（如中转站），可以选任意一家的模型来对照
  const compareModels = models.length ? models : API_MODELS
  const billingOptions = (Object.keys(BILLING_LABEL) as Account['billing'][])
    .filter((v) => v !== 'subscription' || provider.hasSubscription)
    .map((v) => ({ value: v, label: BILLING_LABEL[v] }))

  const pickProvider = (key: string) => {
    const p = providerOf(key)
    const wasDefaultName = PROVIDERS.some((x) => x.name === a.name) || !a.name
    const ms = modelsOf(key)
    const model = ms.find((m) => m.tier === 'balanced') ?? ms[0]
    const base: Partial<Account> = {
      provider: key,
      billing: p.defaultBilling,
      currency: p.currency,
      planId: undefined,
      modelId: model?.id,
      ...(wasDefaultName ? { name: p.name } : {}),
    }
    const ps = plansOf(key)
    const def = p.defaultBilling === 'subscription' ? (ps[1] ?? ps[0]) : undefined
    setA({ ...a, ...base, ...(def ? planPatch(def) : { monthlyCost: 0 }) })
  }

  const planPatch = (p: (typeof plans)[number]): Partial<Account> => ({
    planId: p.id,
    billing: 'subscription',
    monthlyCost: p.price,
    currency: p.currency,
    resetKind: p.resetKind,
    resetHours: p.resetHours ?? a.resetHours,
    resetAnchor: p.resetKind !== 'none' ? (a.resetAnchor ?? new Date().toISOString()) : a.resetAnchor,
  })

  const pickPlan = (planId: string) => {
    const p = plans.find((x) => x.id === planId)
    set(p ? planPatch(p) : { planId: undefined })
  }

  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    const clean: Account = {
      ...a,
      name: a.name.trim() || provider.name,
      monthlyCost: Number(a.monthlyCost) || 0,
      balance: a.billing === 'balance' ? Number(a.balance) || 0 : undefined,
      renewAt: a.billing === 'subscription' ? a.renewAt : undefined,
      planId: a.billing === 'subscription' ? a.planId : undefined,
    }
    if (isNew) await db.accounts.add(clean)
    else await db.accounts.put(clean)
    back('/', isNew ? undefined : `acc-${a.id}`)
  }

  const remove = async () => {
    if (!confirm(`删除「${a.name}」？它的到期项和使用记录也会一起删除。`)) return
    await db.transaction('rw', [db.accounts, db.expiries, db.usage], async () => {
      await db.expiries.where('accountId').equals(a.id!).delete()
      await db.usage.where('accountId').equals(a.id!).delete()
      await db.accounts.delete(a.id!)
    })
    back('/')
  }

  return (
    <form onSubmit={save} className="space-y-5">
      <PageHeader title={isNew ? '添加 AI' : a.name || '编辑'} subtitle={isNew ? '选一家，套餐和价格会自动带出来' : BILLING_LABEL[a.billing]} />

      {!isNew && (
        <div data-shared={`acc-${a.id}`} className="card flex items-center gap-3 p-4!">
          <ProviderBadge provider={a.provider} name={a.name} size={44} />
          <div className="min-w-0">
            <div className="truncate text-[17px] font-semibold">{a.name}</div>
            <div className="truncate text-[13px] text-label-2">{plan ? `${plan.name} · ${plan.limits}` : provider.name}</div>
          </div>
        </div>
      )}

      <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 py-1">
        {PROVIDERS.map((p) => (
          <button
            key={p.key}
            type="button"
            aria-pressed={a.provider === p.key}
            onClick={() => pickProvider(p.key)}
            className="chip shrink-0 py-1.5! pl-1.5!"
          >
            <ProviderBadge provider={p.key} name={p.name} size={24} />
            {p.name}
          </button>
        ))}
      </div>
      {provider.note && <p className="-mt-2 px-1 text-[13px] text-label-2">{provider.note}</p>}

      <div className="card space-y-4">
        <Field label="名称">
          <input className="input" value={a.name} onChange={(e) => set({ name: e.target.value })} placeholder="比如：主力 GPT、XX 中转站" />
        </Field>
        <Field label="计费方式">
          <Segmented value={a.billing} onChange={(billing) => set({ billing })} options={billingOptions} />
        </Field>

        {a.billing === 'subscription' && plans.length > 0 && (
          <div>
            <span className="label">选套餐，价格和重置规则会自动填好</span>
            <div className="space-y-2">
              {plans.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  aria-pressed={a.planId === p.id}
                  onClick={() => pickPlan(a.planId === p.id ? '' : p.id)}
                  className={`press smooth flex w-full items-center gap-3 rounded-[16px] bg-fill-2 p-3 text-left ${
                    a.planId === p.id ? 'shadow-[inset_0_0_0_1.5px_var(--accent)]' : 'shadow-[inset_0_0_0_0.5px_var(--sep)]'
                  }`}
                >
                  <span className="min-w-0 flex-1">
                    <span className="block text-[15px] font-semibold">
                      {p.name}
                      {p.fit && <span className="ml-1.5 text-[12px] font-normal text-label-2">{p.fit}</span>}
                    </span>
                    <span className="mt-0.5 block text-[12px] leading-snug text-label-2">{p.limits}</span>
                  </span>
                  <span className="shrink-0 text-right">
                    <span className="block text-[17px] font-semibold tabular-nums">
                      {p.currency === 'USD' ? '$' : '¥'}
                      {p.price}
                    </span>
                    <span className="block text-[11px] text-label-3">每月</span>
                  </span>
                </button>
              ))}
            </div>
            <p className="mt-2 px-1 text-[12px] text-label-3">
              价格核对于 {plans[0].checked}，以官网为准 ·{' '}
              <a href={plans[0].source} target="_blank" rel="noreferrer" className="text-accent">
                去官网看看
              </a>
            </p>
          </div>
        )}

        <div className="flex gap-3">
          <label className="min-w-0 flex-1">
            <span className="label">{COST_LABEL[a.billing]}</span>
            <input
              className="input tabular-nums"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={a.monthlyCost}
              onChange={(e) => set({ monthlyCost: e.target.value as unknown as number, planId: undefined })}
            />
          </label>
          <label className="w-28">
            <span className="label">币种</span>
            <select className="input" value={a.currency} onChange={(e) => set({ currency: e.target.value as Account['currency'] })}>
              <option value="USD">美元</option>
              <option value="CNY">人民币</option>
            </select>
          </label>
        </div>
        {a.billing === 'subscription' && (
          <Field label="下次续费时间">
            <input className="input" type="datetime-local" value={toLocalInput(a.renewAt)} onChange={(e) => set({ renewAt: fromLocalInput(e.target.value) })} />
          </Field>
        )}
        {a.billing === 'balance' && (
          <Field label="当前余额">
            <input
              className="input tabular-nums"
              type="number"
              inputMode="decimal"
              step="0.01"
              value={a.balance ?? ''}
              onChange={(e) => set({ balance: e.target.value as unknown as number })}
            />
          </Field>
        )}
        {compareModels.length > 0 && (
          <Field label={a.billing === 'subscription' ? '用来对照的 API 模型' : '主要用的模型'} hint="用来估算同样用量按量付费要多少钱">
            <select className="input" value={a.modelId ?? ''} onChange={(e) => set({ modelId: e.target.value || undefined })}>
              <option value="">不对照</option>
              {compareModels.map((m) => (
                <option key={m.id} value={m.id}>
                  {models.length ? m.name : `${providerOf(m.provider).name} ${m.name}`}
                </option>
              ))}
            </select>
          </Field>
        )}
      </div>

      <div className="card space-y-4">
        <Field label="额度重置">
          <Segmented value={a.resetKind} onChange={(resetKind) => set({ resetKind })} options={RESET_OPTIONS} size="sm" />
        </Field>
        {a.resetKind !== 'none' && (
          <>
            {a.resetKind === 'hours' && (
              <Field label="每隔几小时重置">
                <input className="input tabular-nums" type="number" min="1" value={a.resetHours ?? 5} onChange={(e) => set({ resetHours: Number(e.target.value) })} />
              </Field>
            )}
            <Field label="最近一次（或下一次）重置时间">
              <input className="input" type="datetime-local" value={toLocalInput(a.resetAnchor)} onChange={(e) => set({ resetAnchor: fromLocalInput(e.target.value) })} />
            </Field>
            <div className="-mx-4 -mb-4">
              <Toggle label="重置后通知我" checked={a.notifyReset} onChange={(notifyReset) => set({ notifyReset })} />
            </div>
          </>
        )}
      </div>

      <div className="card space-y-4">
        <Field label="在用的模型（选填，会显示在月报上）">
          <input className="input" value={a.models} onChange={(e) => set({ models: e.target.value })} placeholder="随便写，比如常用的模型名" />
        </Field>
        <Field label="备注（选填）">
          <textarea className="input min-h-20" value={a.note} onChange={(e) => set({ note: e.target.value })} />
        </Field>
        <p className="px-1 text-[12px] text-label-3">数据只存在你自己的设备上，不需要也不会保存 API Key。</p>
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

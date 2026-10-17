import { useMemo, useState } from 'react'
import { toCNY, type Intensity } from '../db'
import { useStore } from '../lib/store'
import { API_MODELS, PLANS, PROVIDERS, latestCheck, providerOf, type ApiModel, type Plan } from '../data/pricing'
import { PERSONAS } from '../data/personas'
import { PROFILES, costPerUse, profileOf } from '../lib/value'
import { formatCNY } from '../lib/stats'
import { Segmented, SectionTitle } from '../components/ui'
import ProviderBadge from '../components/ProviderBadge'

const sym = (c: 'USD' | 'CNY') => (c === 'USD' ? '$' : '¥')

/** 一行按量模型：本月估算花费 */
function ModelRow({ m, monthly, best }: { m: ApiModel; monthly: number; best: boolean }) {
  return (
    <div className="row">
      <ProviderBadge provider={m.provider} name={providerOf(m.provider).name} size={30} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[15px]">
          {providerOf(m.provider).name} <span className="text-label-2">{m.name}</span>
        </span>
        <span className="block truncate text-[12px] text-label-3">
          {sym(m.currency)}
          {m.input} 入 / {sym(m.currency)}
          {m.output} 出 · 每百万 token{m.note ? ` · ${m.note}` : ''}
        </span>
      </span>
      <span className={`text-right text-[15px] font-semibold tabular-nums ${best ? 'text-good' : ''}`}>{formatCNY(monthly)}</span>
    </div>
  )
}

function PlanRow({ p, apiBest, rate }: { p: Plan; apiBest?: number; rate: number }) {
  const fee = toCNY(p.price, p.currency, rate)
  const cheaper = apiBest != null && fee < apiBest
  const native = p.currency === 'USD' ? sym('USD') + p.price : null
  return (
    <div className="row">
      <ProviderBadge provider={p.provider} name={providerOf(p.provider).name} size={30} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[15px]">
          {providerOf(p.provider).name} <span className="text-label-2">{p.name}</span>
        </span>
        <span className="block truncate text-[12px] text-label-3">{p.limits}</span>
      </span>
      <span className="text-right">
        <span className={`block text-[15px] font-semibold tabular-nums ${cheaper ? 'text-good' : ''}`}>{formatCNY(fee)}</span>
        <span className="block text-[11px] text-label-3">{native ? `${native}/月` : p.codingOnly ? '编程专用' : p.coding ? '含编程' : '/月'}</span>
      </span>
    </div>
  )
}

export default function Compare() {
  const { settings } = useStore()
  const [personaKey, setPersonaKey] = useState(PERSONAS[0].key)
  const persona = PERSONAS.find((p) => p.key === personaKey)!
  const [intensity, setIntensity] = useState<Intensity>(persona.intensity)
  const [uses, setUses] = useState(persona.usesPerMonth)
  const [region, setRegion] = useState<'all' | 'cn' | 'global'>('all')
  const [showAll, setShowAll] = useState(false)
  const profile = profileOf(intensity)

  const pickPersona = (k: string) => {
    const p = PERSONAS.find((x) => x.key === k)!
    setPersonaKey(k)
    setIntensity(p.intensity)
    setUses(p.usesPerMonth)
  }

  const inRegion = (provider: string) => {
    if (region === 'all') return true
    const cn = ['deepseek', 'kimi', 'glm', 'qwen', 'doubao', 'minimax'].includes(provider)
    return region === 'cn' ? cn : !cn
  }

  const models = useMemo(
    () =>
      API_MODELS.filter((m) => inRegion(m.provider))
        .map((m) => ({ m, monthly: toCNY(costPerUse(profile, m), m.currency, settings.usdRate) * uses }))
        .sort((a, b) => a.monthly - b.monthly),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [profile, uses, settings.usdRate, region],
  )
  // 聊天 / 写作不能用编程专用套餐；写代码 / Agent 只看含编程工具的套餐
  const coding = intensity === 'code' || intensity === 'agent'
  const plans = PLANS.filter((p) => inRegion(p.provider) && (coding ? p.coding : !p.codingOnly)).sort(
    (a, b) => toCNY(a.price, a.currency, settings.usdRate) - toCNY(b.price, b.currency, settings.usdRate),
  )
  const cheapestApi = models[0]?.monthly
  const cheapestPlan = plans[0] ? toCNY(plans[0].price, plans[0].currency, settings.usdRate) : undefined
  const checked = latestCheck()
  const noData = API_MODELS.length === 0 && PLANS.length === 0

  return (
    <div className="space-y-6 pt-4 lg:pt-8">
      <header className="rise px-1" style={{ '--i': 0 } as React.CSSProperties}>
        <p className="eyebrow">{checked ? `价格核对于 ${checked}，以官网为准` : '价格以各家官网为准'}</p>
        <h1 className="display text-[34px]">会员还是按量？</h1>
      </header>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] lg:items-start">
        <div className="space-y-5 lg:sticky lg:top-8 lg:-mx-3 lg:max-h-[calc(100dvh-4rem)] lg:overflow-y-auto lg:px-3 lg:pb-3 no-scrollbar">
          <section className="rise" style={{ '--i': 1 } as React.CSSProperties}>
            <SectionTitle title="你是哪种用法" />
            <div className="grid grid-cols-2 gap-2">
              {PERSONAS.map((p) => (
                <button
                  key={p.key}
                  type="button"
                  aria-pressed={personaKey === p.key}
                  onClick={() => pickPersona(p.key)}
                  className={`card press p-3.5! text-left ${personaKey === p.key ? 'shadow-[inset_0_0_0_1.5px_var(--accent),var(--material-shadow)]!' : ''}`}
                >
                  <span className="block text-[15px] font-semibold">{p.name}</span>
                  <span className="mt-0.5 block text-[12px] leading-snug text-label-2">{p.who}</span>
                </button>
              ))}
            </div>
          </section>

          <section className="card rise space-y-4" style={{ '--i': 2 } as React.CSSProperties}>
            <div>
              <span className="label">主要拿来做什么</span>
              <Segmented<Intensity> size="sm" value={intensity} onChange={setIntensity} options={PROFILES.map((p) => ({ value: p.key, label: p.short }))} />
              <p className="mt-2 px-1 text-[12px] text-label-3">
                {profile.example}。按每次约 {(profile.input / 1000).toFixed(profile.input < 10000 ? 1 : 0)}k 输入 + {(profile.output / 1000).toFixed(1)}k 输出估算（{profile.basis}）。
              </p>
            </div>
            <div>
              <span className="label flex justify-between">
                <span>每月大约用几次</span>
                <span className="tabular-nums text-label">{uses} 次 · 每天约 {Math.round(uses / 30)} 次</span>
              </span>
              <input
                type="range"
                className="slider"
                min={10}
                max={intensity === 'agent' ? 600 : 3000}
                step={10}
                value={Math.min(uses, intensity === 'agent' ? 600 : 3000)}
                style={{ '--p': `${(Math.min(uses, intensity === 'agent' ? 600 : 3000) / (intensity === 'agent' ? 600 : 3000)) * 100}%` } as React.CSSProperties}
                onChange={(e) => setUses(Number(e.target.value))}
              />
            </div>
            <Segmented
              size="sm"
              value={region}
              onChange={setRegion}
              options={[
                { value: 'all', label: '全部' },
                { value: 'cn', label: '国内' },
                { value: 'global', label: '海外' },
              ]}
            />
          </section>

          {!noData && cheapestApi != null && (
            <section className="card rise p-5!" style={{ '--i': 3 } as React.CSSProperties}>
              <span className="eyebrow">结论</span>
              <p className="mt-1 text-[17px] font-semibold leading-snug">
                {cheapestPlan == null
                  ? `按量付费最低每月约 ${formatCNY(cheapestApi)}`
                  : cheapestApi < cheapestPlan
                    ? `按量付费更省：最低每月约 ${formatCNY(cheapestApi)}，比最便宜的会员还少 ${formatCNY(cheapestPlan - cheapestApi)}`
                    : `会员更划算：同样用量按量付费最低也要 ${formatCNY(cheapestApi)}，最便宜的会员 ${formatCNY(cheapestPlan)}`}
              </p>
              <p className="mt-2 text-[13px] text-label-2">{persona.advice}</p>
            </section>
          )}
        </div>

        <div className="space-y-5">
          {noData ? (
            <section className="card rise p-6! text-center" style={{ '--i': 3 } as React.CSSProperties}>
              <p className="text-[15px] font-semibold">价格正在核对</p>
              <p className="mt-1 text-[13px] text-label-2">只收录在官网上核对过的价格，下个版本更新。</p>
            </section>
          ) : (
            <>
              <section className="rise" style={{ '--i': 3 } as React.CSSProperties}>
                <SectionTitle title="按量付费，每月约" right={<span className="text-[12px] text-label-3">{uses} 次 · {profile.label}</span>} />
                <div className="group">
                  {(showAll ? models : models.slice(0, 8)).map(({ m, monthly }, k) => (
                    <ModelRow key={m.id} m={m} monthly={monthly} best={k === 0} />
                  ))}
                  {models.length > 8 && (
                    <button type="button" onClick={() => setShowAll(!showAll)} className="row press w-full justify-center text-[14px] text-accent">
                      {showAll ? '收起' : `显示全部 ${models.length} 个模型`}
                    </button>
                  )}
                </div>
              </section>
              {plans.length > 0 && (
                <section className="rise" style={{ '--i': 4 } as React.CSSProperties}>
                  <SectionTitle title={coding ? '能用来写代码的会员' : '会员订阅'} right={<span className="text-[12px] text-label-3">{plans.length} 个</span>} />
                  <div className="group">
                    {plans.map((p) => (
                      <PlanRow key={p.id} p={p} apiBest={cheapestApi} rate={settings.usdRate} />
                    ))}
                  </div>
                  <p className="mt-2 px-4 text-[12px] text-label-3">会员有用量上限（见每行小字），超过就要等重置；按量付费没有上限，但用多少付多少。</p>
                </section>
              )}
              <section className="rise" style={{ '--i': 5 } as React.CSSProperties}>
                <SectionTitle title="怎么算的" />
                <div className="card space-y-2 text-[13px] leading-relaxed text-label-2">
                  <p>
                    按量费用 = 每月次数 × 每次 token 数 × 官方单价。每次「{profile.label}」约 {Math.round(profile.input / 1000)}k 输入、{(profile.output / 1000).toFixed(1)}k 输出，其中 {Math.round(profile.cacheRatio * 100)}% 的输入按缓存命中价算。
                  </p>
                  <p>美元按设置里的汇率 1 美元 = {settings.usdRate} 元换算。DeepSeek 按高峰时段价（贵的那档）计，空闲时段用会再省一半。</p>
                  <p>会员的用量上限各家都没公开具体数字，只能看官方给的倍数和窗口；碰到上限要等重置，或者另买额度。</p>
                </div>
              </section>

              <section className="rise" style={{ '--i': 6 } as React.CSSProperties}>
                <SectionTitle title="价格来源" />
                <div className="group">
                  {PROVIDERS.filter((p) => API_MODELS.some((m) => m.provider === p.key) || PLANS.some((x) => x.provider === p.key)).map((p) => {
                    const src = [...PLANS, ...API_MODELS].find((x) => x.provider === p.key)!
                    return (
                      <a key={p.key} href={src.source} target="_blank" rel="noreferrer" className="row press">
                        <span className="flex-1 text-[15px]">{p.name}</span>
                        <span className="text-[12px] text-label-3">核对于 {src.checked}</span>
                        <span className="text-[13px] text-accent">官网 ›</span>
                      </a>
                    )
                  })}
                </div>
              </section>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

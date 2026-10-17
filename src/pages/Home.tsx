import dayjs from 'dayjs'
import { db, type Account, type Intensity } from '../db'
import { useStore } from '../lib/store'
import { BILLING_LABEL } from '../presets'
import { buildTimeline, countdown, nextReset, type EventKind } from '../lib/time'
import { formatCNY, formatMoney, monthlySpend } from '../lib/stats'
import { useNow } from '../lib/useNow'
import { useCountUp } from '../lib/useCountUp'
import { useGo } from '../lib/useGo'
import { PROFILES, valueReport } from '../lib/value'
import { API_MODELS, plansOf } from '../data/pricing'
import ProviderBadge from '../components/ProviderBadge'
import { Amount, SectionTitle } from '../components/ui'

const KIND: Record<EventKind, { label: string; color: string }> = {
  expiry: { label: '到期', color: 'var(--expiry)' },
  renew: { label: '续费', color: 'var(--renew)' },
  reset: { label: '重置', color: 'var(--reset)' },
}

/** 圆环：离事件越近越满 */
function Ring({ progress, color, size = 40 }: { progress: number; color: string; size?: number }) {
  const r = 15
  const c = 2 * Math.PI * r
  return (
    <svg viewBox="0 0 36 36" width={size} height={size} className="shrink-0 -rotate-90">
      <circle cx="18" cy="18" r={r} fill="none" strokeWidth="3.5" style={{ stroke: 'var(--fill)' }} />
      <circle
        cx="18"
        cy="18"
        r={r}
        fill="none"
        strokeWidth="3.5"
        strokeLinecap="round"
        strokeDasharray={c}
        strokeDashoffset={c * (1 - progress)}
        style={{ stroke: color, transition: 'stroke-dashoffset var(--dur-spring) var(--ease-spring)' }}
      />
    </svg>
  )
}

/** 主账号的焦点卡：下一次重置倒计时 + 这周期用得值不值 + 一键记一次 */
function Focus({ a, now }: { a: Account; now: dayjs.Dayjs }) {
  const { link } = useGo()
  const { settings, usage: allUsage } = useStore()
  const usage = allUsage.filter((u) => u.accountId === a.id)
  const model = API_MODELS.find((m) => m.id === a.modelId)
  const plan = plansOf(a.provider).find((p) => p.id === a.planId)
  const report = valueReport(a, usage, settings, model, now)
  const reset = nextReset(a, now)
  const today = now.format('YYYY-MM-DD')
  const todayCount = usage.filter((u) => u.day === today).reduce((s, u) => s + u.count, 0)

  const log = async (intensity: Intensity) => {
    const row = await db.usage.where('[accountId+day]').equals([a.id!, today]).and((u) => u.intensity === intensity).first()
    if (row) await db.usage.update(row.id!, { count: row.count + 1 })
    else await db.usage.add({ accountId: a.id!, day: today, count: 1, intensity })
    navigator.vibrate?.(8)
  }

  const resetSpan = a.resetKind === 'hours' ? (a.resetHours ?? 5) * 60 : a.resetKind === 'weekly' ? 7 * 1440 : 30 * 1440
  const resetProgress = reset ? 1 - Math.min(1, reset.diff(now, 'minute') / resetSpan) : 0
  const ratio = report.fee > 0 && report.apiEquivalent > 0 ? report.apiEquivalent / report.fee : 0

  return (
    <section className="card rise space-y-4 p-5!" style={{ '--i': 1 } as React.CSSProperties}>
      <a href={`#/account/${a.id}`} onClick={link(`/account/${a.id}`, `acc-${a.id}`)} className="press -m-1 flex items-center gap-3 rounded-[18px] p-1">
        <span data-shared={`acc-${a.id}`} className="flex min-w-0 flex-1 items-center gap-3">
          <ProviderBadge provider={a.provider} name={a.name} size={44} />
          <span className="min-w-0">
            <span className="block truncate text-[17px] font-semibold">{a.name}</span>
            <span className="block truncate text-[13px] text-label-2">{plan ? `${plan.name} · ${plan.limits}` : BILLING_LABEL[a.billing]}</span>
          </span>
        </span>
        <svg viewBox="0 0 24 24" className="h-4 w-4 shrink-0 text-label-3" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
          <path d="m9 6 6 6-6 6" />
        </svg>
      </a>

      {reset && (
        <div className="flex items-center gap-4 rounded-[18px] bg-fill-2 p-4 smooth">
          <Ring progress={resetProgress} color="var(--reset)" size={52} />
          <div className="min-w-0 flex-1">
            <div className="display text-[28px]">{countdown(reset, now)}</div>
            <div className="text-[12px] text-label-3">重置于 {reset.format('M月D日 HH:mm')}</div>
          </div>
        </div>
      )}

      <div>
        <div className="flex items-baseline justify-between">
          <span className="text-[13px] font-medium text-label-2">这个月用得值不值</span>
          <span className="text-[12px] text-label-3">已过 {Math.round(report.elapsed * 100)}%</span>
        </div>
        {report.verdict === 'unknown' ? (
          <p className="mt-1.5 text-[14px] text-label-2">
            {model ? '每次用完点一下下面的按钮，用几天就能算出会员值不值。' : '在账号里选一个对照的 API 模型，就能算出同样用量按量付费要多少钱。'}
          </p>
        ) : (
          <>
            <div className="mt-1 flex items-baseline gap-2">
              <Amount value={formatCNY(report.apiEquivalent)} className="text-[30px]" />
              <span className="text-[13px] text-label-2">按量付费等价 · 会员 {formatCNY(report.fee)}</span>
            </div>
            <div className="mt-2.5 h-2 overflow-hidden rounded-full bg-fill">
              <div
                className="h-full rounded-full"
                style={{
                  width: `${Math.min(100, ratio * 100)}%`,
                  background: report.verdict === 'great' ? 'var(--good)' : report.verdict === 'ok' ? 'var(--accent)' : 'var(--expiry)',
                  transition: 'width var(--dur-spring) var(--ease-spring)',
                }}
              />
            </div>
            <p className="mt-2 text-[13px] text-label-2">
              {report.verdict === 'great' && '用量已经超过月费，会员比按量付费划算。'}
              {report.verdict === 'ok' && '用到月费的一半以上了，再多用点就回本。'}
              {report.verdict === 'low' && '按目前用量，换成按量付费会更省。'}
              {report.limitDays > 0 && ` 这周期有 ${report.limitDays} 天碰到了上限。`}
            </p>
          </>
        )}
      </div>

      <div>
        <div className="flex items-baseline justify-between">
          <span className="text-[13px] font-medium text-label-2">记一次</span>
          <span className="text-[12px] text-label-3">{todayCount > 0 ? `今天 ${todayCount} 次` : ""}</span>
        </div>
        <div className="mt-2 grid grid-cols-4 gap-2">
          {PROFILES.map((p) => (
            <button key={p.key} type="button" onClick={() => log(p.key)} className="press rounded-[14px] bg-fill-2 px-1 py-2.5 text-[12px] font-medium smooth active:bg-fill">
              {p.short}
            </button>
          ))}
        </div>
      </div>
    </section>
  )
}

export default function Home() {
  const now = dayjs(useNow())
  const { link } = useGo()
  const { accounts, expiries, settings } = useStore()
  const { total, slices } = monthlySpend(accounts, settings)
  const shownTotal = useCountUp(total, 'spend')

  const timeline = buildTimeline(accounts, expiries, now)
  const upcoming = timeline.filter((e) => e.at.isAfter(now))
  const overdue = timeline.filter((e) => e.kind === 'expiry' && !e.at.isAfter(now))
  const windowHours = Math.max(settings.remindHours * 3, 24)
  // 焦点账号：有订阅就取最贵的订阅，否则第一个
  const focus = [...accounts].filter((a) => a.billing === 'subscription').sort((x, y) => y.monthlyCost - x.monthlyCost)[0] ?? accounts[0]
  const others = accounts.filter((a) => a !== focus)
  let i = 2
  const next = () => ({ '--i': i++ }) as React.CSSProperties

  return (
    <div className="grid grid-cols-1 gap-5 pt-4 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)] lg:items-start lg:gap-6 lg:pt-8">
      <div className="space-y-5">
        <header className="rise flex items-end justify-between px-1" style={{ '--i': 0 } as React.CSSProperties}>
          <div>
            <p className="text-[13px] text-label-3">{now.format('M月D日 dddd')}</p>
            <h1 className="display text-[34px]">概览</h1>
          </div>
          <a href="#/account/new" onClick={link('/account/new')} className="btn-plain px-4! py-2! text-[14px]" aria-label="添加 AI">
            <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round">
              <path d="M12 5v14M5 12h14" />
            </svg>
            添加
          </a>
        </header>

        {accounts.length === 0 ? (
          <section className="card rise space-y-3 px-6! py-10! text-center" style={{ '--i': 1 } as React.CSSProperties}>
            <div className="mx-auto grid h-16 w-16 place-items-center rounded-[20px] bg-accent-soft text-accent smooth">
              <svg viewBox="0 0 24 24" className="h-8 w-8" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1" />
              </svg>
            </div>
            <h2 className="text-[20px] font-semibold">先加一个你在用的 AI</h2>
            <p className="text-[14px] text-label-2">只订了一个会员也够用：看额度什么时候重置、这个月用得值不值、换成按量付费会不会更省。</p>
            <div className="flex justify-center gap-2 pt-2">
              <a href="#/account/new" onClick={link('/account/new')} className="btn-primary">
                添加 AI
              </a>
              <a href="#/compare" onClick={link('/compare')} className="btn-plain">
                先看看比价
              </a>
            </div>
          </section>
        ) : (
          <Focus a={focus} now={now} />
        )}

        {accounts.length > 1 && (
          <section className="rise" style={next()}>
            <SectionTitle title="其他 AI" />
            <div className="group">
              {others.map((a) => (
                <a key={a.id} href={`#/account/${a.id}`} onClick={link(`/account/${a.id}`, `acc-${a.id}`)} className="row press">
                  <span data-shared={`acc-${a.id}`} className="flex min-w-0 flex-1 items-center gap-3">
                    <ProviderBadge provider={a.provider} name={a.name} size={34} />
                    <span className="min-w-0">
                      <span className="block truncate text-[15px] font-medium">{a.name}</span>
                      <span className="block truncate text-[12px] text-label-2">
                        {BILLING_LABEL[a.billing]}
                        {a.billing === 'balance' && a.balance != null && ` · 余额 ${formatMoney(a.balance, a.currency)}`}
                      </span>
                    </span>
                  </span>
                  <span className="text-[15px] tabular-nums text-label-2">{formatMoney(a.monthlyCost, a.currency)}</span>
                </a>
              ))}
            </div>
          </section>
        )}
      </div>

      <div className="space-y-5 lg:sticky lg:top-8">
        {accounts.length > 0 && (
          <a href="#/card" onClick={link('/card', 'spend')} className="card press rise block p-5!" style={next()}>
            <div data-shared="spend">
              <div className="flex items-baseline justify-between">
                <span className="eyebrow">本月花费</span>
                <span className="text-[13px] text-accent">月报 ›</span>
              </div>
              <Amount value={formatCNY(shownTotal)} className="mt-1 block text-[44px]" />
              <div className="mt-3 flex h-2 gap-[3px] overflow-hidden rounded-full">
                {total > 0 ? (
                  slices.map((s) => <span key={s.account.id} className="min-w-[4px] first:rounded-l-full last:rounded-r-full" style={{ flexGrow: s.cny, background: s.color }} />)
                ) : (
                  <span className="flex-1 rounded-full bg-fill" />
                )}
              </div>
              <div className="mt-2.5 flex flex-wrap gap-x-4 gap-y-1">
                {slices.slice(0, 4).map((s) => (
                  <span key={s.account.id} className="flex items-center gap-1.5 text-[12px] text-label-2">
                    <span className="h-2 w-2 rounded-full" style={{ background: s.color }} />
                    {s.account.name}
                  </span>
                ))}
              </div>
            </div>
          </a>
        )}

        {overdue.length > 0 && (
          <section className="rise" style={next()}>
            <SectionTitle title="已过期" />
            <div className="group">
              {overdue.map((e) => (
                <a key={e.key} href={`#/expiry/${e.expiryId}`} onClick={link(`/expiry/${e.expiryId}`)} className="row press">
                  <span className="h-2 w-2 shrink-0 rounded-full bg-danger" />
                  <span className="min-w-0 flex-1 truncate text-[15px]">{e.title}</span>
                  <span className="text-[13px] text-label-2">{e.at.format('M/D')}</span>
                </a>
              ))}
            </div>
          </section>
        )}

        {upcoming.length > 0 && (
          <section className="rise" style={next()}>
            <SectionTitle
              title="接下来"
              right={
                <a href="#/expiry/new" onClick={link('/expiry/new')} className="text-[14px] text-accent">
                  添加到期项
                </a>
              }
            />
            <div className="group">
              {upcoming.slice(0, 8).map((e) => {
                const hours = e.at.diff(now, 'minute') / 60
                const urgent = e.kind !== 'reset' && hours < settings.remindHours
                const to = e.expiryId != null ? `/expiry/${e.expiryId}` : `/account/${e.accountId}`
                const k = KIND[e.kind]
                return (
                  <a key={e.key} href={`#${to}`} onClick={link(to)} className="row press">
                    <Ring progress={Math.max(0.04, 1 - hours / windowHours)} color={k.color} size={32} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[15px]">{e.title}</span>
                      <span className="block text-[12px] text-label-2">
                        {k.label} · {e.at.format('M月D日 HH:mm')}
                      </span>
                    </span>
                    <span className={`text-[15px] font-medium tabular-nums ${urgent ? 'text-expiry' : 'text-label'}`}>{countdown(e.at, now)}</span>
                  </a>
                )
              })}
            </div>
          </section>
        )}
      </div>
    </div>
  )
}

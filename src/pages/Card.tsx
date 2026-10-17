import { useRef, useState } from 'react'
import dayjs from 'dayjs'
import { toPng } from 'html-to-image'
import { useStore } from '../lib/store'
import { Capacitor } from '@capacitor/core'
import { formatCNY, monthlySpend } from '../lib/stats'
import { Amount } from '../components/ui'
import { useCountUp } from '../lib/useCountUp'

async function shareImage(dataUrl: string, filename: string) {
  if (Capacitor.isNativePlatform()) {
    const { Filesystem, Directory } = await import('@capacitor/filesystem')
    const { Share } = await import('@capacitor/share')
    const saved = await Filesystem.writeFile({ path: filename, data: dataUrl.split(',')[1], directory: Directory.Cache })
    await Share.share({ title: '我的 AI 月度花费', files: [saved.uri] })
    return
  }
  const blob = await (await fetch(dataUrl)).blob()
  const file = new File([blob], filename, { type: 'image/png' })
  if (navigator.canShare?.({ files: [file] })) {
    await navigator.share({ files: [file], title: '我的 AI 月度花费' })
    return
  }
  const a = document.createElement('a')
  a.href = dataUrl
  a.download = filename
  a.click()
}

export default function Card() {
  const { accounts, settings } = useStore()
  const { total, slices } = monthlySpend(accounts, settings)
  const shown = useCountUp(total, 'spend')
  const cardRef = useRef<HTMLDivElement>(null)
  const [tilt, setTilt] = useState({ x: 0, y: 0 })
  const [busy, setBusy] = useState(false)
  const month = dayjs().format('YYYY.MM')
  const serial = `TKF-${dayjs().format('YYMM')}-${String(Math.round(total)).padStart(5, '0')}`
  const models = [...new Set(accounts.flatMap((a) => a.models.split(/[,，、/]/).map((m) => m.trim())).filter(Boolean))]
  const daily = total / dayjs().daysInMonth()

  const onMove = (e: React.PointerEvent) => {
    const r = e.currentTarget.getBoundingClientRect()
    setTilt({ x: ((e.clientY - r.top) / r.height - 0.5) * -7, y: ((e.clientX - r.left) / r.width - 0.5) * 9 })
  }

  const exportCard = async () => {
    if (!cardRef.current) return
    setBusy(true)
    try {
      const url = await toPng(cardRef.current, { pixelRatio: 3, cacheBust: true })
      await shareImage(url, `ai-spend-${dayjs().format('YYYY-MM')}.png`)
    } catch (err) {
      if ((err as Error).name !== 'AbortError') alert('生成图片失败：' + (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="mx-auto max-w-md space-y-5 pt-4 lg:pt-8">
      <header className="rise px-1" style={{ '--i': 0 } as React.CSSProperties}>
        <p className="eyebrow">{month}</p>
        <h1 className="display text-[34px]">月报</h1>
      </header>

      {/* 卡片随指针轻微倾斜，高光反向移动，像 Apple Wallet 里的卡 */}
      <div
        data-shared="spend"
        className="rise [perspective:1100px]"
        style={{ '--i': 1 } as React.CSSProperties}
        onPointerMove={onMove}
        onPointerLeave={() => setTilt({ x: 0, y: 0 })}
      >
        <div
          style={{
            transform: `rotateX(${tilt.x}deg) rotateY(${tilt.y}deg)`,
            transition: 'transform var(--dur-spring) var(--ease-spring)',
            transformStyle: 'preserve-3d',
          }}
        >
          {/* 导出的节点：全部用纯 CSS 画，html-to-image 才能截到 */}
          <div
            ref={cardRef}
            data-theme="dark"
            className="smooth relative aspect-[3/4] overflow-hidden rounded-[32px] bg-[#101218] text-white shadow-[0_30px_60px_-24px_rgb(10_12_30/0.55)]"
          >
            <div className="absolute -left-20 -top-16 h-80 w-80 rounded-full bg-[#5b5bd6] opacity-70 blur-[80px]" />
            <div className="absolute -right-24 top-20 h-72 w-72 rounded-full bg-[#2f6fd8] opacity-55 blur-[80px]" />
            <div className="absolute -bottom-24 right-4 h-80 w-80 rounded-full bg-[#1fa2a8] opacity-45 blur-[90px]" />
            {/* 斜向流光，跟着倾斜角移动 */}
            <div
              className="pointer-events-none absolute inset-0 mix-blend-soft-light"
              style={{
                background: `linear-gradient(115deg, transparent 30%, rgb(255 255 255 / 0.35) ${48 + tilt.y * 2}%, transparent ${66 + tilt.y * 2}%)`,
              }}
            />
            <div className="pointer-events-none absolute inset-0 rounded-[32px] shadow-[inset_0_0_0_0.5px_rgb(255_255_255/0.18),inset_0_1px_0_rgb(255_255_255/0.25)]" />

            <div className="relative flex h-full flex-col p-7">
              <div className="flex items-center justify-between text-[13px] text-white/70">
                <span className="font-semibold text-white">Tokenfield</span>
                <span>{month}</span>
              </div>

              <div className="mt-8">
                <div className="text-[15px] text-white/75">这个月我在 AI 上花了</div>
                <Amount value={formatCNY(shown)} className="mt-1 block text-[64px]" />
                <div className="mt-1 text-[13px] text-white/60">
                  平均每天 {formatCNY(daily)} · {accounts.length} 个 AI
                </div>
              </div>

              <div className="mt-auto rounded-[22px] bg-white/[0.08] p-4 backdrop-blur-md smooth shadow-[inset_0_0_0_0.5px_rgb(255_255_255/0.16),inset_0_1px_0_rgb(255_255_255/0.2)]">
                <div className="flex h-2 gap-[3px] overflow-hidden rounded-full">
                  {slices.map((s) => (
                    <span key={s.account.id} className="min-w-[4px]" style={{ flexGrow: s.cny || 0.0001, background: s.color }} />
                  ))}
                </div>
                <ul className="mt-3.5 space-y-2.5 text-[14px]">
                  {slices.slice(0, 4).map((s) => (
                    <li key={s.account.id} className="flex items-center gap-2.5">
                      <span className="h-2.5 w-2.5 rounded-full" style={{ background: s.color }} />
                      <span className="flex-1 truncate">{s.account.name}</span>
                      <span className="font-semibold tabular-nums">{formatCNY(s.cny)}</span>
                      <span className="w-10 text-right text-[12px] tabular-nums text-white/55">{total ? Math.round((s.cny / total) * 100) : 0}%</span>
                    </li>
                  ))}
                  {slices.length > 4 && <li className="pl-5 text-white/55">还有 {slices.length - 4} 个</li>}
                </ul>
                {models.length > 0 && (
                  <div className="mt-3.5 flex flex-wrap gap-1.5">
                    {models.slice(0, 6).map((m) => (
                      <span key={m} className="rounded-full bg-white/12 px-2.5 py-0.5 text-[12px] text-white/85">
                        {m}
                      </span>
                    ))}
                  </div>
                )}
              </div>

              <div className="mt-4 flex items-center justify-between text-[12px] text-white/60">
                <span className="truncate">{settings.handle ? `@${settings.handle.replace(/^@/, '')}` : 'Tokenfield 额度终端'}</span>
                <span className="font-mono">{serial}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {accounts.length === 0 && <p className="text-center text-[14px] text-label-2">先在概览里添加你在用的 AI，月报会自动生成。</p>}

      <button type="button" onClick={exportCard} disabled={busy || accounts.length === 0} className="btn-primary rise w-full" style={{ '--i': 2 } as React.CSSProperties}>
        {busy ? '正在生成' : '保存 / 分享图片'}
      </button>
    </div>
  )
}

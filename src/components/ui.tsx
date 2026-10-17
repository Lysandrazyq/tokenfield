import { useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { go } from '../lib/transition'
import LiquidGlass from './LiquidGlass'

/** 详情页顶栏：左上液态玻璃返回键 + 大标题。标题带 view-transition-name，接住上一页被点的元素 */
export function PageHeader({ title, subtitle, shared, right }: { title: string; subtitle?: string; shared?: string; right?: ReactNode }) {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  return (
    <header className="flex items-center gap-3 pt-3">
      <LiquidGlass
        as="button"
        type="button"
        radius={999}
        bezel={14}
        strength={26}
        onClick={() => go(navigate, history.length > 1 ? -1 : '/', { from: pathname, to: '/' })}
        className="press grid h-11 w-11 shrink-0 place-items-center text-label"
        aria-label="返回"
      >
        <svg viewBox="0 0 24 24" className="relative h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
          <path d="M14.5 5.5 8 12l6.5 6.5" />
        </svg>
      </LiquidGlass>
      <div className="min-w-0 flex-1">
        <h1 className="display truncate text-[26px]" style={shared ? { viewTransitionName: shared } : undefined}>
          {title}
        </h1>
        {subtitle && <p className="truncate text-[13px] text-label-2">{subtitle}</p>}
      </div>
      {right}
    </header>
  )
}

/** 区块标题：iOS 分组标题的样式 */
export function SectionTitle({ title, right }: { title: string; right?: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between px-1 pb-2.5">
      <h2 className="text-[15px] font-semibold tracking-[0.01em] text-label-2 uppercase">{title}</h2>
      {right}
    </div>
  )
}

export function Field({ label, hint, children }: { label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <label className="block">
      <span className="label">{label}</span>
      {children}
      {hint && <span className="mt-1.5 block px-1 text-[12px] text-label-3">{hint}</span>}
    </label>
  )
}

/** 分段控件：选中块是一颗会滑动的白色胶囊（iOS UISegmentedControl），用全站同一条弹簧 */
export function Segmented<T extends string>({
  value,
  options,
  onChange,
  size = 'md',
}: {
  value: T
  options: { value: T; label: string }[]
  onChange: (v: T) => void
  size?: 'sm' | 'md'
}) {
  const wrap = useRef<HTMLDivElement>(null)
  const [pill, setPill] = useState<{ left: number; width: number } | null>(null)

  useLayoutEffect(() => {
    const el = wrap.current?.querySelector<HTMLButtonElement>(`[data-v="${value}"]`)
    if (el) setPill({ left: el.offsetLeft, width: el.offsetWidth })
  }, [value, options.length])

  return (
    <div ref={wrap} role="radiogroup" className="relative flex rounded-full bg-fill-2 p-[3px] shadow-[inset_0_0_0_0.5px_var(--sep)]">
      {pill && (
        <span
          aria-hidden
          className="absolute top-[3px] bottom-[3px] rounded-full bg-white shadow-[0_3px_8px_rgb(0_0_0/0.12),0_3px_1px_rgb(0_0_0/0.04)] dark:bg-[#636366]"
          style={{
            left: pill.left,
            width: pill.width,
            transition: 'left var(--dur-spring) var(--ease-spring), width var(--dur-spring) var(--ease-spring)',
          }}
        />
      )}
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          data-v={o.value}
          onClick={() => onChange(o.value)}
          className={`relative flex-1 whitespace-nowrap rounded-full px-2 font-medium transition-colors duration-200 ${size === 'sm' ? 'py-1.5 text-[13px]' : 'py-2 text-[14px]'} ${
            value === o.value ? 'text-label' : 'text-label-2'
          }`}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

export function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <button type="button" role="switch" aria-checked={checked} onClick={() => onChange(!checked)} className="row w-full text-left">
      <span className="min-w-0 flex-1">
        <span className="block text-[15px]">{label}</span>
        {hint && <span className="block text-[12px] text-label-2">{hint}</span>}
      </span>
      <span className="switch" aria-checked={checked}>
        <span />
      </span>
    </button>
  )
}

/** 带单位的大数字：数字用 display 字体，单位小一号 */
export function Amount({ value, className = '' }: { value: string; className?: string }) {
  const m = value.match(/^([^\d-]*)(-?[\d,.]+)(.*)$/)
  if (!m) return <span className={className}>{value}</span>
  return (
    <span className={`display ${className}`}>
      <span className="mr-[0.06em] text-[0.55em] font-semibold align-[0.32em] opacity-70">{m[1]}</span>
      {m[2]}
      {m[3] && <span className="ml-0.5 text-[0.5em] opacity-70">{m[3]}</span>}
    </span>
  )
}

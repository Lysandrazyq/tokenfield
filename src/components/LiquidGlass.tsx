import { useId, useLayoutEffect, useRef, useState, type CSSProperties, type ElementType, type ReactNode } from 'react'
import { useAppearance } from '../lib/appearance'

/**
 * Apple 式液态玻璃：边缘折射 + 高光边。
 *
 * 做法（参考 kube.io「Refraction with CSS and SVG」）：
 *   1. 把玻璃边缘看成一圈 squircle 截面的凸透镜：高度 h(x) = ⁴√(1-(1-x)⁴)，x 是到边缘的归一化距离。
 *   2. 对每个像素求表面法线，按斯涅尔定律（n=1.5）算出光线偏折量，编码进位移图的 R/G 通道。
 *   3. SVG feDisplacementMap 用这张图扭曲背景，作为 backdrop-filter 挂在元素上。
 *
 * 只有 Chromium 支持 backdrop-filter: url(#svg)。其他浏览器只用 .liquid 的磨砂 + 高光，观感降级但成立。
 * 位移图按元素尺寸生成并缓存，尺寸变了才重算。
 */

const supportsSvgBackdrop = (() => {
  if (typeof navigator === 'undefined') return false
  // Safari / Firefox 会解析 url() 但不渲染；只在 Chromium 上开
  const ua = navigator.userAgent
  return /Chrome\/|Chromium\/|Edg\//.test(ua) && !/Firefox\//.test(ua)
})()

const reduceTransparency = () => matchMedia('(prefers-reduced-transparency: reduce)').matches

const cache = new Map<string, string>()

/** 生成位移图（data URL）。w/h 是 CSS 像素，r 是圆角，bezel 是折射带宽度 */
function displacementMap(w: number, h: number, r: number, bezel: number) {
  const key = `${w}x${h}r${r}b${bezel}`
  const hit = cache.get(key)
  if (hit) return hit

  // 半分辨率生成，feImage 拉伸回去；位移图本身是平滑的，看不出差别
  const s = 0.5
  const cw = Math.max(2, Math.round(w * s))
  const ch = Math.max(2, Math.round(h * s))
  const canvas = document.createElement('canvas')
  canvas.width = cw
  canvas.height = ch
  const ctx = canvas.getContext('2d')!
  const img = ctx.createImageData(cw, ch)

  const height = (x: number) => Math.pow(1 - Math.pow(1 - x, 4), 0.25)
  const slope = (x: number) => {
    const e = 0.001
    return (height(Math.min(1, x + e)) - height(Math.max(0, x - e))) / (2 * e)
  }
  const n = 1.5
  // 预计算：到边缘距离 d（0..bezel）→ 偏折量
  const steps = 64
  const table: number[] = []
  let max = 0
  for (let i = 0; i <= steps; i++) {
    const x = i / steps
    const theta1 = Math.atan(slope(x) * 0.6)
    const theta2 = Math.asin(Math.sin(theta1) / n)
    const shift = Math.tan(theta1 - theta2) * (1 - height(x) * 0.4)
    table.push(shift)
    max = Math.max(max, Math.abs(shift))
  }

  const rr = Math.min(r, w / 2, h / 2)
  for (let py = 0; py < ch; py++) {
    for (let px = 0; px < cw; px++) {
      const x = (px + 0.5) / s
      const y = (py + 0.5) / s
      // 到圆角矩形边界的有符号距离 + 指向边界外的法线
      const qx = Math.abs(x - w / 2) - (w / 2 - rr)
      const qy = Math.abs(y - h / 2) - (h / 2 - rr)
      let nx = 0, ny = 0, dist
      if (qx > 0 && qy > 0) {
        const len = Math.hypot(qx, qy)
        dist = rr - len
        nx = qx / (len || 1)
        ny = qy / (len || 1)
      } else if (qx > qy) {
        dist = rr - qx
        nx = 1
      } else {
        dist = rr - qy
        ny = 1
      }
      nx *= Math.sign(x - w / 2) || 1
      ny *= Math.sign(y - h / 2) || 1
      const o = (py * cw + px) * 4
      let dx = 0, dy = 0
      if (dist >= 0 && dist < bezel) {
        const k = table[Math.round((dist / bezel) * steps)] / (max || 1)
        // 光线往内偏折：采样点往外走，背景看起来被"拉进"边缘
        dx = nx * k
        dy = ny * k
      }
      img.data[o] = 128 + dx * 127
      img.data[o + 1] = 128 + dy * 127
      img.data[o + 2] = 128
      img.data[o + 3] = 255
    }
  }
  ctx.putImageData(img, 0, 0)
  const url = canvas.toDataURL()
  cache.set(key, url)
  return url
}

export default function LiquidGlass<T extends ElementType = 'div'>({
  as,
  radius = 999,
  bezel = 18,
  strength = 38,
  className = '',
  style,
  children,
  ...rest
}: {
  as?: T
  /** 圆角（px），999 表示胶囊 */
  radius?: number
  /** 折射带宽度（px） */
  bezel?: number
  /** 位移强度（px） */
  strength?: number
  className?: string
  style?: CSSProperties
  children?: ReactNode
} & Omit<React.ComponentPropsWithoutRef<T>, 'as' | 'className' | 'style' | 'children'>) {
  const Tag = (as ?? 'div') as ElementType
  const ref = useRef<HTMLElement>(null)
  const rawId = useId()
  const id = `lg${rawId.replace(/[^a-zA-Z0-9]/g, '')}`
  const [size, setSize] = useState<{ w: number; h: number } | null>(null)
  const { refraction } = useAppearance()
  const enabled = refraction && supportsSvgBackdrop && !reduceTransparency()

  useLayoutEffect(() => {
    if (!enabled || !ref.current) return
    const el = ref.current
    setSize({ w: el.offsetWidth, h: el.offsetHeight })
    const ro = new ResizeObserver(([e]) => {
      const w = Math.round(e.borderBoxSize?.[0]?.inlineSize ?? el.offsetWidth)
      const h = Math.round(e.borderBoxSize?.[0]?.blockSize ?? el.offsetHeight)
      setSize((s) => (s && s.w === w && s.h === h ? s : { w, h }))
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [enabled])

  const r = Math.min(radius, size ? Math.min(size.w, size.h) / 2 : radius)
  const map = enabled && size && size.w > 4 ? displacementMap(size.w, size.h, r, Math.min(bezel, Math.min(size.w, size.h) / 2)) : null
  const filter = map ? `url(#${id}) blur(0.6px) saturate(180%) brightness(1.04)` : undefined

  return (
    <Tag
      ref={ref}
      className={`liquid ${className}`}
      style={{ borderRadius: radius, ...(filter ? { backdropFilter: filter, WebkitBackdropFilter: filter } : null), ...style }}
      {...rest}
    >
      {map && size && (
        <svg aria-hidden width="0" height="0" className="absolute">
          <filter id={id} x="0" y="0" width={size.w} height={size.h} filterUnits="userSpaceOnUse" colorInterpolationFilters="sRGB">
            <feImage href={map} x="0" y="0" width={size.w} height={size.h} result="map" preserveAspectRatio="none" />
            <feGaussianBlur in="SourceGraphic" stdDeviation="2.5" result="soft" />
            <feDisplacementMap in="soft" in2="map" scale={strength} xChannelSelector="R" yChannelSelector="G" />
          </filter>
        </svg>
      )}
      {children}
    </Tag>
  )
}

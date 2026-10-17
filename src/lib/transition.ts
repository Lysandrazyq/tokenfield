import { flushSync } from 'react-dom'
import type { NavigateFunction, To } from 'react-router-dom'

/**
 * 全站唯一的转场入口。
 *
 * 方向规则（空间一致性：从哪来回哪去）：
 *   - tab 之间：按 tab 顺序左右横移；
 *   - tab → 详情：forward（新页从右推入，旧页往左退一点并缩小）；
 *   - 详情 → tab：back（原路退回）。
 * 共享元素：带 data-shared="xxx" 的元素在新旧两页之间直接变形（AI 卡片飞到详情页顶部，返回时飞回原位）。
 */

export const TAB_ORDER = ['/', '/compare', '/card', '/settings']

const depth = (path: string) => (TAB_ORDER.includes(path) ? 0 : 1)

export function directionOf(from: string, to: string): 'forward' | 'back' | 'left' | 'right' | 'none' {
  if (from === to) return 'none'
  const a = depth(from), b = depth(to)
  if (b > a) return 'forward'
  if (b < a) return 'back'
  const i = TAB_ORDER.indexOf(from), j = TAB_ORDER.indexOf(to)
  if (i >= 0 && j >= 0) return j > i ? 'right' : 'left'
  return 'forward'
}

const canTransition = () =>
  typeof document !== 'undefined' && 'startViewTransition' in document && !matchMedia('(prefers-reduced-motion: reduce)').matches

const sharedEl = (name: string) => document.querySelector<HTMLElement>(`[data-shared="${CSS.escape(name)}"]`)

let running = false

export function go(
  navigate: NavigateFunction,
  to: To | number,
  opts: { from: string; to?: string; replace?: boolean; shared?: string },
) {
  const target = typeof to === 'number' ? (opts.to ?? '/') : typeof to === 'string' ? to.split('?')[0] : (to.pathname ?? '/')
  const doNav = () => (typeof to === 'number' ? navigate(to) : navigate(to, { replace: opts.replace }))
  if (!canTransition() || running) {
    doNav()
    return
  }
  running = true
  const root = document.documentElement
  root.dataset.dir = directionOf(opts.from, target)
  const name = opts.shared
  const old = name ? sharedEl(name) : null
  if (old && name) old.style.viewTransitionName = name
  // 首次进场动画还没播完就切页：先停掉它，否则入场动画和转场叠在一起会闪
  root.classList.remove('booting')
  const vt = document.startViewTransition(() => {
    // 数据在内存里（lib/store），flushSync 之后新页已经完整渲染，没有空帧
    flushSync(doNav)
    const next = name ? sharedEl(name) : null
    if (next && name && next !== old) next.style.viewTransitionName = name
  })
  // 转场被浏览器跳过（比如标签页在后台）时不要留下脏状态
  vt.ready.catch(() => {})
  vt.finished.finally(() => {
    running = false
    delete root.dataset.dir
    if (name) {
      const el = sharedEl(name)
      if (el) el.style.viewTransitionName = ''
    }
  })
}

/** 首次打开：错峰入场只播一次，之后切页由 View Transition 负责 */
export function markBooted() {
  const root = document.documentElement
  root.classList.add('booting')
  const t = setTimeout(() => root.classList.remove('booting'), 1400)
  return () => clearTimeout(t)
}

export const isBooting = () => document.documentElement.classList.contains('booting')

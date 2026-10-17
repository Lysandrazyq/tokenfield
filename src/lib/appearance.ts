import { useSyncExternalStore } from 'react'

/**
 * 外观偏好单独存 localStorage（不进 IndexedDB）：
 * index.html 里的内联脚本要在首帧前同步读到主题，避免浅色用户看到一闪黑屏。
 */

export type ThemeMode = 'system' | 'light' | 'dark'

export interface Appearance {
  theme: ThemeMode
  /** 液态玻璃边缘折射（只在 Chromium 内核生效，低端机可以关掉省电） */
  refraction: boolean
}

export const DEFAULT_APPEARANCE: Appearance = { theme: 'system', refraction: true }

const KEY = 'tkf-appearance'
const listeners = new Set<() => void>()
const darkQuery = matchMedia('(prefers-color-scheme: dark)')

function read(): Appearance {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) || '{}')
    return { theme: raw.theme ?? DEFAULT_APPEARANCE.theme, refraction: raw.refraction ?? DEFAULT_APPEARANCE.refraction }
  } catch {
    return DEFAULT_APPEARANCE
  }
}

let current = read()

export function resolvedTheme(a: Appearance = current): 'light' | 'dark' {
  return a.theme === 'system' ? (darkQuery.matches ? 'dark' : 'light') : a.theme
}

/** 把主题写到 <html data-theme>，并同步浏览器/系统栏颜色 */
function apply() {
  const t = resolvedTheme()
  document.documentElement.dataset.theme = t
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', t === 'dark' ? '#0a0b10' : '#f2f3f7')
}

darkQuery.addEventListener('change', () => {
  if (current.theme !== 'system') return
  apply()
  listeners.forEach((l) => l())
})
apply()

export function setAppearance(patch: Partial<Appearance>) {
  const next = { ...current, ...patch }
  const themeChanged = next.theme !== current.theme
  current = next
  localStorage.setItem(KEY, JSON.stringify(current))
  // 明暗切换用一次全屏交叉淡化，不让每个元素各自过渡颜色
  if (themeChanged && 'startViewTransition' in document && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.startViewTransition(() => {
      apply()
      listeners.forEach((l) => l())
    })
    return
  }
  apply()
  listeners.forEach((l) => l())
}

const subscribe = (l: () => void) => {
  listeners.add(l)
  return () => listeners.delete(l)
}

export function useAppearance() {
  return useSyncExternalStore(subscribe, () => current)
}

/** 当前生效的明暗（system 时跟着系统变） */
export function useTheme() {
  return useSyncExternalStore(subscribe, () => resolvedTheme())
}

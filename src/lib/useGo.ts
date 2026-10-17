import { useCallback } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { go } from './transition'

/**
 * 页面里统一用这个跳转，保证都走同一套转场。
 * link(to, shared) 返回 onClick，可直接挂在 <a href> 上（保留原生链接语义：中键、长按都正常）。
 */
export function useGo() {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const to = useCallback(
    (target: string, opts: { replace?: boolean; shared?: string } = {}) => go(navigate, target, { from: pathname, ...opts }),
    [navigate, pathname],
  )
  const back = useCallback(
    (fallback = '/', shared?: string) =>
      go(navigate, history.length > 1 ? -1 : fallback, { from: pathname, to: fallback, shared }),
    [navigate, pathname],
  )
  const link = useCallback(
    (target: string, shared?: string) => (e: React.MouseEvent) => {
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return
      e.preventDefault()
      to(target, { shared })
    },
    [to],
  )
  return { to, back, link }
}

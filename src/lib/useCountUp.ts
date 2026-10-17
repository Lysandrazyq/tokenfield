import { useEffect, useRef, useState } from 'react'

const easeOut = (x: number) => 1 - Math.pow(1 - x, 4)

/**
 * 数字只在「真的变了」时滚动过去。
 * 上一次显示的值按 key 记在模块里：切页回来组件重新挂载，也直接显示上次的数，不会从 0 再数一遍。
 */
const last = new Map<string, number>()

export function useCountUp(target: number, key = 'default', duration = 900) {
  const prev = last.get(key)
  const [value, setValue] = useState(prev ?? target)
  const from = useRef(prev ?? target)

  useEffect(() => {
    const begin = from.current
    last.set(key, target)
    if (begin === target || matchMedia('(prefers-reduced-motion: reduce)').matches) {
      from.current = target
      setValue(target)
      return
    }
    const start = performance.now()
    let raf = 0
    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / duration)
      const v = begin + (target - begin) * easeOut(p)
      from.current = v
      setValue(v)
      if (p < 1) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [target, key, duration])

  return value
}

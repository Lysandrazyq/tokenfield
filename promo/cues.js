/*
 * 宣传片的分镜表（画面和声音共用同一份时间点）。
 * 浏览器里作为普通脚本加载（挂到 globalThis.CUES），Node 里 import 后读 globalThis.CUES。
 *
 * 一条主线：先抛问题 → 看自己的额度 → 切到比价看答案（高潮：液态玻璃透镜扫过结论）→ 一键月报 → 落版。
 * 镜头之间的切换全部沿用 App 里的规则：tab 往右切，新内容从右边推进来，旧内容往左退。
 */
globalThis.CUES = {
  duration: 10,
  fps: 30,
  beats: [
    { t: 0.06, id: 'q1', sound: 'tick', note: '问题第一句' },
    { t: 0.42, id: 'q2', sound: 'tick', note: '问题第二句' },
    { t: 1.55, id: 'cards', sound: 'rise', note: '问题收到顶部，额度卡片升起' },
    { t: 2.05, id: 'list', sound: 'tick', note: '账号列表' },
    { t: 3.9, id: 'tab-compare', sound: 'switch', note: '底栏切到「比价」' },
    { t: 4.35, id: 'bar1', sound: 'tick' },
    { t: 4.5, id: 'bar2', sound: 'tick' },
    { t: 4.65, id: 'bar3', sound: 'tick' },
    { t: 5.55, id: 'lens', sound: 'glide', note: '高潮：液态玻璃透镜滑过' },
    { t: 6.5, id: 'verdict', sound: 'chime', note: '结论出现' },
    { t: 7.15, id: 'tab-report', sound: 'switch', note: '切到「月报」' },
    { t: 8.55, id: 'end', sound: 'swell', note: '落版' },
  ],
}

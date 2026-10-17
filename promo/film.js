/* global CUES */
/*
 * Tokenfield 宣传片：每一帧都是时间 t 的纯函数（render(t)），没有实时时钟、没有随机数。
 * 动效只用一条弹簧（与 App 相同：response 0.5s / damping 0.82），透明度用短的 ease-out。
 */
const Q = new URLSearchParams(location.search)
const P = Q.get('layout') === 'portrait'
const W = P ? 1080 : 1920
const H = P ? 1920 : 1080
const DUR = CUES.duration
const B = Object.fromEntries(CUES.beats.map((b) => [b.id, b.t]))

// ---------- 时间函数 ----------
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x))
const lerp = (a, b, k) => a + (b - a) * k
function springAt(x, response = 0.5, zeta = 0.82) {
  if (x <= 0) return 0
  const w0 = (2 * Math.PI) / response
  if (zeta >= 1) return 1 - Math.exp(-w0 * x) * (1 + w0 * x)
  const wd = w0 * Math.sqrt(1 - zeta * zeta)
  return 1 - Math.exp(-zeta * w0 * x) * (Math.cos(wd * x) + ((zeta * w0) / wd) * Math.sin(wd * x))
}
const sp = (t, t0, r, z) => springAt(t - t0, r, z)
const easeOut = (x) => 1 - Math.pow(1 - clamp(x), 3)
const sine = (x) => -(Math.cos(Math.PI * clamp(x)) - 1) / 2
const fade = (t, t0, d = 0.32) => easeOut((t - t0) / d)
/** 进场后在 t1 退场：进场 opacity+位移 用弹簧，退场用 ease-out */
const life = (t, t0, t1, d = 0.3) => (t < t0 ? 0 : t1 != null && t >= t1 ? 1 - fade(t, t1, d) : 1)

// ---------- DOM 工具 ----------
function h(tag, style = {}, kids = [], cls = '') {
  const e = document.createElement(tag)
  if (cls) e.className = cls
  Object.assign(e.style, style)
  for (const k of [].concat(kids)) if (k != null) e.append(k)
  return e
}
const box = (style, kids, cls = '') => h('div', { position: 'absolute', ...style }, kids, `abs ${cls}`.trim())
const tx = (s, style = {}, cls = '') => h('div', style, [s], cls)
function put(e, { x = 0, y = 0, s = 1, o = 1, rx = 0, ry = 0 } = {}) {
  e.style.transform = `translate3d(${x}px, ${y}px, 0)` + (s !== 1 ? ` scale(${s})` : '') + (rx || ry ? ` perspective(1400px) rotateX(${rx}deg) rotateY(${ry}deg)` : '')
  e.style.opacity = o
}
const money = (n) => '¥' + Math.round(n).toLocaleString('en-US')

// ---------- 背景：和 App 同一套极光，按 t 推进 ----------
const VERT = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}'
const FRAG = `
precision highp float;
uniform vec2 res; uniform float t; uniform vec2 c[5]; uniform float r[5]; uniform vec3 cols[5];
const vec3 base = vec3(0.038, 0.043, 0.063);
float hash(vec2 q){ return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453); }
void main(){
  vec2 uv = gl_FragCoord.xy / res;
  vec2 span = res / min(res.x, res.y);
  vec2 q = uv * span;
  vec3 acc = vec3(0.0); float ws = 0.0;
  for (int i = 0; i < 5; i++) { vec2 d = q - c[i] * span; float w = exp(-dot(d, d) / (r[i] * r[i])); acc += cols[i] * w; ws += w; }
  vec3 hue = acc / max(ws, 1e-4);
  vec3 col = mix(base, hue, (1.0 - exp(-ws * 0.95)) * 0.58);
  float v = smoothstep(1.3, 0.2, length((uv - 0.5) * span / max(span.x, span.y) * 1.6));
  col *= mix(0.62, 1.0, v);
  // 1/255 级别的抖动，配合 grain 层防止色带
  col += (hash(gl_FragCoord.xy + fract(t * 7.13) * 97.0) - 0.5) * (2.0 / 255.0);
  gl_FragColor = vec4(col, 1.0);
}`
const PATHS = [
  { pts: [[0.12, 0.82], [0.45, 0.95], [0.4, 0.55], [0.08, 0.5]], period: 34, radius: 0.5, phase: 0.0 },
  { pts: [[0.88, 0.86], [0.96, 0.55], [0.66, 0.6], [0.72, 0.96]], period: 28, radius: 0.44, phase: 0.3 },
  { pts: [[0.82, 0.18], [0.55, 0.04], [0.5, 0.36], [0.96, 0.4]], period: 38, radius: 0.42, phase: 0.6 },
  { pts: [[0.18, 0.14], [0.04, 0.4], [0.35, 0.36], [0.4, 0.04]], period: 24, radius: 0.4, phase: 0.15 },
  { pts: [[0.5, 0.5], [0.66, 0.3], [0.34, 0.24], [0.45, 0.7]], period: 40, radius: 0.3, phase: 0.8 },
]
const COLS = ['#3b3a8f', '#1f3f7a', '#155e6e', '#4a2f80', '#5b5bd6']
function blobAt(i, time) {
  const { pts, period, phase } = PATHS[i]
  const n = pts.length
  const f = (((time / period + phase) % 1) + 1) % 1
  const seg = Math.floor(f * n), s = f * n - seg
  const p0 = pts[(seg - 1 + n) % n], p1 = pts[seg], p2 = pts[(seg + 1) % n], p3 = pts[(seg + 2) % n]
  const b1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
  const b2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
  const u = 1 - s
  return [0, 1].map((k) => u * u * u * p1[k] + 3 * u * u * s * b1[k] + 3 * u * s * s * b2[k] + s * s * s * p2[k])
}
let drawBg = () => {}
function initBg() {
  const cv = document.getElementById('bg')
  cv.width = W
  cv.height = H
  const gl = cv.getContext('webgl', { preserveDrawingBuffer: true, antialias: false })
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s }
  const pr = gl.createProgram()
  gl.attachShader(pr, sh(gl.VERTEX_SHADER, VERT))
  gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, FRAG))
  gl.linkProgram(pr)
  gl.useProgram(pr)
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer())
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
  const loc = gl.getAttribLocation(pr, 'p')
  gl.enableVertexAttribArray(loc)
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0)
  const U = (n) => gl.getUniformLocation(pr, n)
  const hex = (c) => [1, 3, 5].map((k) => parseInt(c.slice(k, k + 2), 16) / 255)
  gl.uniform3fv(U('cols'), COLS.flatMap(hex))
  gl.uniform2f(U('res'), W, H)
  gl.viewport(0, 0, W, H)
  drawBg = (t) => {
    const time = 22 + t * 1.6
    const cs = [], rs = []
    for (let i = 0; i < 5; i++) {
      cs.push(...blobAt(i, time))
      rs.push(PATHS[i].radius * (1 + 0.08 * Math.sin((time / PATHS[i].period) * Math.PI * 4 + i)))
    }
    gl.uniform1f(U('t'), t)
    gl.uniform2fv(U('c'), cs)
    gl.uniform1fv(U('r'), rs)
    gl.drawArrays(gl.TRIANGLES, 0, 3)
  }
}
// ---------- 构建场景（只建一次，每帧只改 transform / opacity / 文本） ----------
const S = {} // 所有要动的节点
const L = P
  ? { cx: W / 2, cardW: 900, top: 330, qY: 760, qSize: 92, tabY: H - 210 }
  : { cx: W / 2, cardW: 820, top: 150, qY: 430, qSize: 96, tabY: H - 150 }

function badge(letter, color, size) {
  return h('div', {
    width: size + 'px', height: size + 'px', borderRadius: size * 0.28 + 'px', fontSize: size * 0.42 + 'px',
    background: `linear-gradient(160deg, color-mix(in oklab, ${color} 82%, white), ${color})`,
    boxShadow: `inset 0 1px 0 rgb(255 255 255 / 0.45), 0 8px 24px -10px ${color}`, flexShrink: 0,
  }, [letter], 'badge')
}

function ring(size, color) {
  const r = 15, c = 2 * Math.PI * r
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
  svg.setAttribute('viewBox', '0 0 36 36')
  svg.setAttribute('width', size)
  svg.setAttribute('height', size)
  svg.style.transform = 'rotate(-90deg)'
  svg.innerHTML = `<circle cx="18" cy="18" r="${r}" fill="none" stroke="rgb(120 120 128 / 0.24)" stroke-width="3.4"/>
    <circle class="arc" cx="18" cy="18" r="${r}" fill="none" stroke="${color}" stroke-width="3.4" stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${c}"/>`
  svg.setProgress = (p) => svg.querySelector('.arc').setAttribute('stroke-dashoffset', String(c * (1 - p)))
  return svg
}

function build() {
  const layer = document.getElementById('layer')
  const stage = document.getElementById('stage')
  stage.style.width = W + 'px'
  stage.style.height = H + 'px'
  const add = (k, e) => (layer.append(e), (S[k] = e))

  // 1. 问题
  const qStyle = { fontSize: L.qSize + 'px', fontWeight: 650, letterSpacing: '-0.035em', lineHeight: 1.08, whiteSpace: 'nowrap' }
  add('q1', box({ left: 0, top: 0, width: W + 'px', textAlign: 'center' }, [tx('AI 会员', qStyle)]))
  add('q2', box({ left: 0, top: 0, width: W + 'px', textAlign: 'center' }, [tx('到底值不值？', { ...qStyle, color: 'var(--label-2)' })]))

  // 2. 额度焦点卡（和 App 概览同款）
  const cw = L.cardW
  const focus = box({ left: L.cx - cw / 2 + 'px', top: 0, width: cw + 'px', padding: '40px' }, [
    h('div', { display: 'flex', alignItems: 'center', gap: '24px' }, [
      badge('C', '#d97757', 84),
      h('div', {}, [tx('Claude Pro', { fontSize: '40px', fontWeight: 650 }), tx('每 5 小时一个用量窗口 · 含 Claude Code', { fontSize: '24px', color: 'var(--label-2)', marginTop: '4px' })]),
    ]),
    h('div', { display: 'flex', alignItems: 'center', gap: '30px', marginTop: '32px', padding: '30px', borderRadius: '30px', background: 'var(--fill-2)' }, [
      (S.ring = ring(108, 'var(--reset)')),
      h('div', {}, [tx('下次额度重置', {}, 'eyebrow'), (S.cd = tx('1 时 47 分', { fontSize: '62px', marginTop: '4px' }, 'display'))]),
    ]),
    h('div', { marginTop: '32px' }, [
      h('div', { display: 'flex', justifyContent: 'space-between' }, [tx('本周期用得值不值', {}, 'eyebrow'), tx('已过 60%', { fontSize: '22px', color: 'var(--label-3)' })]),
      h('div', { display: 'flex', alignItems: 'baseline', gap: '18px', marginTop: '6px' }, [
        (S.val = tx('¥0', { fontSize: '76px' }, 'display')),
        tx('按量付费等价 · 会员 ¥142', { fontSize: '24px', color: 'var(--label-2)' }),
      ]),
      h('div', { height: '14px', borderRadius: '99px', background: 'var(--fill)', marginTop: '18px', overflow: 'hidden' }, [
        (S.bar = h('div', { height: '100%', width: '0%', borderRadius: '99px', background: 'var(--good)' })),
      ]),
    ]),
  ], 'card')
  add('focus', focus)

  // 3. 账号列表
  const rows = [
    ['X', '#8e7cf0', 'XX 中转站', '中转站余额 · 余额 ¥37.5', '¥100'],
    ['D', '#4d6bfe', 'DeepSeek', '按量付费 · 工作时段以外半价', '¥12'],
  ]
  S.rows = rows.map(([l, c, n, s, v]) =>
    h('div', {}, [badge(l, c, 64), h('div', { flex: 1 }, [tx(n, { fontSize: '32px', fontWeight: 600 }), tx(s, { fontSize: '22px', color: 'var(--label-2)' })]), tx(v, { fontSize: '32px', color: 'var(--label-2)', fontVariantNumeric: 'tabular-nums' })], 'row'),
  )
  add('list', box({ left: L.cx - cw / 2 + 'px', top: 0, width: cw + 'px', padding: '8px 0', overflow: 'hidden' }, S.rows, 'card'))

  // 4. 比价：横条图（每月 180 次 Agent 任务）
  const bars = [
    ['Claude Opus 5.5 按量付费', '#d97757', 1799, '¥1,799'],
    ['Claude Max 5x 会员', '#d97757', 710, '¥710'],
    ['GLM Coding Lite 会员', '#3859ff', 118, '¥118'],
  ]
  const maxV = 1799
  S.bars = bars.map(([n, c, v, label]) => {
    const fill = h('div', { height: '100%', width: '0%', borderRadius: '99px', background: `linear-gradient(90deg, color-mix(in oklab, ${c} 70%, white), ${c})` })
    const num = tx(label, { fontSize: '40px', fontWeight: 650, fontVariantNumeric: 'tabular-nums' })
    const row = h('div', { marginTop: '34px' }, [
      h('div', { display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }, [tx(n, { fontSize: '28px', color: 'var(--label-2)' }), num]),
      h('div', { height: '22px', borderRadius: '99px', background: 'var(--fill-2)', marginTop: '12px', overflow: 'hidden' }, [fill]),
    ])
    row.fill = fill
    row.target = v / maxV
    return row
  })
  add('compare', box({ left: L.cx - cw / 2 + 'px', top: 0, width: cw + 'px', padding: '44px' }, [
    tx('编程 Agent · 每月 180 个任务', {}, 'eyebrow'),
    tx('会员还是按量？', { fontSize: '58px', marginTop: '8px' }, 'display'),
    ...S.bars,
    (S.verdict = h('div', { marginTop: '40px', padding: '28px 32px', borderRadius: '28px', background: 'color-mix(in oklab, var(--good) 16%, transparent)', boxShadow: 'inset 0 0 0 1.5px color-mix(in oklab, var(--good) 50%, transparent)' }, [
      tx('会员更划算，一个月省 ¥1,089', { fontSize: '36px', fontWeight: 650, color: 'var(--good)' }),
      tx('按官网价格逐条核对 · 2026-10-10', { fontSize: '22px', color: 'var(--label-2)', marginTop: '6px' }),
    ])),
  ], 'card'))

  // 5. 月报卡（App 里的月报同款）
  add('report', box({ left: L.cx - 330 + 'px', top: 0, width: '660px', height: '880px', borderRadius: '56px', overflow: 'hidden', background: '#101218', boxShadow: '0 60px 120px -40px rgb(0 0 0 / 0.7)' }, [
    h('div', { position: 'absolute', left: '-140px', top: '-120px', width: '560px', height: '560px', borderRadius: '50%', background: '#5b5bd6', opacity: 0.7, filter: 'blur(110px)' }),
    h('div', { position: 'absolute', right: '-160px', top: '160px', width: '480px', height: '480px', borderRadius: '50%', background: '#1f3f7a', opacity: 0.6, filter: 'blur(110px)' }),
    h('div', { position: 'absolute', right: '20px', bottom: '-180px', width: '560px', height: '560px', borderRadius: '50%', background: '#155e6e', opacity: 0.5, filter: 'blur(120px)' }),
    (S.sheen = h('div', { position: 'absolute', inset: 0, mixBlendMode: 'soft-light' })),
    h('div', { position: 'absolute', inset: 0, borderRadius: 'inherit', boxShadow: 'inset 0 0 0 1px rgb(255 255 255 / 0.16), inset 0 1.5px 0 rgb(255 255 255 / 0.25)' }),
    h('div', { position: 'absolute', inset: 0, padding: '56px', display: 'flex', flexDirection: 'column' }, [
      h('div', { display: 'flex', justifyContent: 'space-between', fontSize: '26px' }, [tx('Tokenfield', { fontWeight: 650 }), tx('2026.10', { color: 'rgb(255 255 255 / 0.7)' })]),
      tx('这个月我在 AI 上花了', { fontSize: '30px', color: 'rgb(255 255 255 / 0.75)', marginTop: '70px' }),
      (S.repTotal = tx('¥0', { fontSize: '128px', marginTop: '6px' }, 'display')),
      tx('平均每天 ¥8 · 3 个 AI', { fontSize: '26px', color: 'rgb(255 255 255 / 0.6)', marginTop: '6px' }),
      h('div', { marginTop: 'auto', padding: '32px', borderRadius: '36px', background: 'rgb(255 255 255 / 0.08)', boxShadow: 'inset 0 0 0 1px rgb(255 255 255 / 0.14)' }, [
        h('div', { display: 'flex', gap: '5px', height: '16px', borderRadius: '99px', overflow: 'hidden' }, [
          h('span', { flex: 142, background: '#d97757' }), h('span', { flex: 100, background: '#8e7cf0' }), h('span', { flex: 12, background: '#4d6bfe' }),
        ]),
        ...[['#d97757', 'Claude Pro', '¥142'], ['#8e7cf0', 'XX 中转站', '¥100'], ['#4d6bfe', 'DeepSeek', '¥12']].map(([c, n, v]) =>
          h('div', { display: 'flex', alignItems: 'center', gap: '18px', marginTop: '22px', fontSize: '28px' }, [
            h('span', { width: '18px', height: '18px', borderRadius: '50%', background: c }), h('span', { flex: 1 }, [n]), h('span', { fontWeight: 650 }, [v]),
          ]),
        ),
      ]),
    ]),
  ]))

  // 6. 液态玻璃透镜（高潮）：真正的折射用 SVG 位移滤镜，按 squircle 截面 + 斯涅尔定律生成位移图
  S.lensSize = P ? 380 : 340
  add('lens', box({ left: 0, top: 0, width: S.lensSize + 'px', height: S.lensSize + 'px', borderRadius: '50%', backdropFilter: 'url(#lensF) saturate(115%) brightness(1.03)', boxShadow: 'inset 0 2px 1px rgb(255 255 255 / 0.26), inset 0 -3px 4px rgb(255 255 255 / 0.09), inset 0 0 0 1px rgb(255 255 255 / 0.16), 0 24px 50px -18px rgb(0 0 0 / 0.4)' }, [
    h('div', { position: 'absolute', inset: 0, borderRadius: '50%', background: 'radial-gradient(50% 38% at 30% 20%, rgb(255 255 255 / 0.19), transparent 65%), radial-gradient(32% 24% at 72% 82%, rgb(255 255 255 / 0.05), transparent 65%)', mixBlendMode: 'soft-light' }),
  ]))
  buildLensFilter(S.lensSize)

  // 7. 底部液态玻璃 tab 栏
  const tabs = ['概览', '比价', '月报', '设置']
  S.tabItems = tabs.map((n) => tx(n, { flex: 1, textAlign: 'center', fontSize: '28px', fontWeight: 600, position: 'relative', zIndex: 1, padding: '24px 0', color: 'var(--label-2)' }))
  S.tabPill = h('div', { position: 'absolute', top: '10px', bottom: '10px', borderRadius: '99px', background: 'var(--fill)' })
  add('tabs', box({ left: L.cx - 340 + 'px', top: 0, width: '680px', padding: '10px', borderRadius: '999px', display: 'flex' }, [S.tabPill, ...S.tabItems], 'liquid'))

  // 8. 落版
  add('logo', box({ left: 0, top: 0, width: W + 'px', textAlign: 'center' }, [
    tx('Tokenfield', { fontSize: P ? '128px' : '150px' }, 'display'),
    tx('额度终端', { fontSize: P ? '44px' : '48px', letterSpacing: '0.4em', color: 'var(--label-2)', marginTop: '18px', paddingLeft: '0.4em' }),
  ]))
  add('tag', box({ left: 0, top: 0, width: W + 'px', textAlign: 'center' }, [
    tx('看额度、比价格、出月报，一个 App 搞定', { fontSize: P ? '34px' : '36px', color: 'var(--label)' }),
  ]))
  const facts = [['10 家', 'AI 服务商'], ['44 个', '套餐和模型价格'], ['0', '上传的数据']]
  S.factCards = facts.map(([a, b]) =>
    h('div', { textAlign: 'center', padding: P ? '28px 34px' : '26px 44px', borderRadius: '30px', minWidth: P ? '260px' : '280px' }, [
      tx(a, { fontSize: P ? '54px' : '56px' }, 'display'),
      tx(b, { fontSize: '24px', color: 'var(--label-2)', marginTop: '6px' }),
    ], 'liquid'),
  )
  add('factsRow', box({ left: 0, top: 0, width: W + 'px', display: 'flex', justifyContent: 'center', gap: '24px', flexWrap: P ? 'wrap' : 'nowrap' }, S.factCards))
}

function buildLensFilter(size) {
  /*
   * 位移图：凸透镜。
   *   中心：均匀放大 1.18 倍（采样点往圆心收）。
   *   边缘：squircle 截面 h(x)=⁴√(1-(1-x)⁴)，按斯涅尔定律（n=1.5）算偏折，只在外圈 22% 半径内发生。
   * 位移按像素算好后再归一化，最后用 Float 精度写入 R/G 通道（128 为零点）。
   */
  const n = 512
  const cv = document.createElement('canvas')
  cv.width = cv.height = n
  const ctx = cv.getContext('2d')
  const img = ctx.createImageData(n, n)
  const R = n / 2
  const bezel = 0.22 * R
  const zoom = 1 / 1.18
  const hgt = (x) => Math.pow(1 - Math.pow(1 - x, 4), 0.25)
  const refr = (x) => {
    const e = 1e-3
    const slope = (hgt(Math.min(1, x + e)) - hgt(Math.max(0, x - e))) / (2 * e)
    const t1 = Math.atan(slope), t2 = Math.asin(Math.sin(t1) / 1.5)
    return Math.tan(t1 - t2)
  }
  const maxRef = refr(0.001)
  const vecs = new Float32Array(n * n * 2)
  let maxD = 0
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const dx = x + 0.5 - R, dy = y + 0.5 - R
    const r = Math.hypot(dx, dy)
    let ox = 0, oy = 0
    if (r < R) {
      // 放大：采样点 = r * zoom，位移 = r*zoom - r（指向圆心）
      let shift = r * zoom - r
      const fromEdge = R - r
      if (fromEdge < bezel) shift -= (refr(fromEdge / bezel) / maxRef) * bezel * 0.9
      const ux = r ? dx / r : 0, uy = r ? dy / r : 0
      ox = ux * shift
      oy = uy * shift
    }
    vecs[(y * n + x) * 2] = ox
    vecs[(y * n + x) * 2 + 1] = oy
    maxD = Math.max(maxD, Math.abs(ox), Math.abs(oy))
  }
  for (let i = 0; i < n * n; i++) {
    img.data[i * 4] = 128 + (vecs[i * 2] / maxD) * 127
    img.data[i * 4 + 1] = 128 + (vecs[i * 2 + 1] / maxD) * 127
    img.data[i * 4 + 2] = 128
    img.data[i * 4 + 3] = 255
  }
  ctx.putImageData(img, 0, 0)
  // feDisplacementMap 的 scale = 最大位移（换算到实际尺寸）× 2
  const scale = (maxD / n) * size * 2
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
  svg.setAttribute('width', 0)
  svg.setAttribute('height', 0)
  svg.style.position = 'absolute'
  // 色散：R/B 通道位移强度差 ±6%，只在边缘明显（中心位移小，差值也小）
  svg.innerHTML = `<filter id="lensF" x="0" y="0" width="${size}" height="${size}" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
    <feImage href="${cv.toDataURL()}" x="0" y="0" width="${size}" height="${size}" result="map" preserveAspectRatio="none"/>
    <feGaussianBlur in="map" stdDeviation="1.2" result="smap"/>
    <feDisplacementMap in="SourceGraphic" in2="smap" scale="${scale}" xChannelSelector="R" yChannelSelector="G" result="g"/>
    <feDisplacementMap in="SourceGraphic" in2="smap" scale="${scale * 1.06}" xChannelSelector="R" yChannelSelector="G" result="r"/>
    <feDisplacementMap in="SourceGraphic" in2="smap" scale="${scale * 0.94}" xChannelSelector="R" yChannelSelector="G" result="b"/>
    <feColorMatrix in="r" type="matrix" values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0" result="rr"/>
    <feColorMatrix in="g" type="matrix" values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0" result="gg"/>
    <feColorMatrix in="b" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0" result="bb"/>
    <feBlend in="rr" in2="gg" mode="screen" result="rg"/>
    <feBlend in="rg" in2="bb" mode="screen"/>
  </filter>`
  document.body.append(svg)
}
// ---------- 每一帧 ----------
/*
 * 节拍（秒）：
 *   0.06  问题第一句升起            0.42 第二句
 *   1.55  问题缩到顶部，额度卡升起 → 倒计时环填满、价值条长出
 *   3.90  底栏切到「比价」：卡片整体往左推，比价从右推进（App 里 tab 往右切的规则）
 *   4.35+ 三根横条依次长出
 *   5.55  高潮：液态玻璃透镜从左滑到右，经过横条时把数字放大、边缘折射
 *   6.50  结论出现
 *   7.15  切到「月报」：月报卡从右推进，带 3D 倾斜和流光
 *   8.55  一切收回，落版：Tokenfield 额度终端 + 一句话，保持到 10s
 */
function render(t) {
  drawBg(t)
  const pushX = P ? W * 0.9 : W * 0.62 // tab 切换时内容横移的距离

  // 问题
  const qy = L.qY
  const q1 = sp(t, B.q1), q2 = sp(t, B.q2)
  const up = sp(t, B.cards, 0.6, 1) // 问题往上收
  const qShrink = lerp(1, P ? 0.5 : 0.42, up)
  const qTop = lerp(qy - L.qSize * 0.6, P ? 170 : 58, up)
  const qOut = t > B['tab-compare'] ? fade(t, B['tab-compare'], 0.3) : 0
  put(S.q1, { x: 0, y: qTop + (1 - q1) * 30, o: fade(t, B.q1, 0.4) * (1 - qOut), s: qShrink })
  put(S.q2, { x: 0, y: qTop + L.qSize * 1.12 * qShrink + (1 - q2) * 30, o: fade(t, B.q2, 0.4) * (1 - qOut), s: qShrink })
  S.q1.style.transformOrigin = S.q2.style.transformOrigin = '50% 0'

  // 第一屏：额度卡 + 列表
  const k1 = sp(t, B.cards)
  const toCompare = sp(t, B['tab-compare'])
  const shiftA = -toCompare * pushX * 0.35 // 旧页往左退一点（App 规则：退 10% 左右 + 淡出）
  const top1 = P ? 560 : 300
  const showA = fade(t, B.cards, 0.35) * (1 - fade(t, B['tab-compare'], 0.35))
  put(S.focus, { x: shiftA, y: top1 + (1 - k1) * 90, o: showA, s: lerp(0.96, 1, k1) - toCompare * 0.03 })
  const k2 = sp(t, B.list)
  put(S.list, P
    ? { x: shiftA, y: top1 + 700 + (1 - k2) * 70, o: fade(t, B.list, 0.35) * (1 - fade(t, B['tab-compare'], 0.35)) }
    : { x: shiftA, y: top1 + 40 + (1 - k2) * 70, o: fade(t, B.list, 0.35) * (1 - fade(t, B['tab-compare'], 0.35)) })
  if (!P) {
    // 横屏两张卡并排：额度卡 820 + 间距 40 + 列表 640，整组水平居中
    const gx = (W - (L.cardW + 40 + 640)) / 2
    S.focus.style.left = gx + 'px'
    S.list.style.left = gx + L.cardW + 40 + 'px'
    S.list.style.width = '640px'
  }
  // 环和数字
  const ringP = sp(t, B.cards + 0.25, 0.9, 1)
  S.ring.setProgress(0.04 + 0.62 * ringP)
  const valP = sp(t, B.cards + 0.35, 0.9, 1)
  S.val.textContent = '¥' + (15.7 * valP).toFixed(1)
  S.bar.style.width = 11 * valP + '%'
  // 倒计时每秒走一格，体现「活的」
  const mins = 107 - Math.floor(clamp(t - B.cards, 0, 9) * 0.5)
  S.cd.textContent = `${Math.floor(mins / 60)} 时 ${String(mins % 60).padStart(2, '0')} 分`

  // 第二屏：比价
  const toReport = sp(t, B['tab-report'])
  const inB = toCompare
  const shiftB = (1 - inB) * pushX - toReport * pushX * 0.35
  const showB = fade(t, B['tab-compare'] + 0.05, 0.35) * (1 - fade(t, B['tab-report'], 0.35))
  const topB = P ? 380 : 120
  put(S.compare, { x: shiftB, y: topB, o: showB, s: 1 - toReport * 0.03 })
  ;['bar1', 'bar2', 'bar3'].forEach((id, i) => {
    const k = sp(t, B[id], 0.7, 0.86)
    S.bars[i].fill.style.width = S.bars[i].target * 100 * k + '%'
    S.bars[i].style.opacity = fade(t, B[id] - 0.08, 0.3)
  })
  const kv = sp(t, B.verdict)
  S.verdict.style.opacity = fade(t, B.verdict, 0.3)
  S.verdict.style.transform = `translateY(${(1 - kv) * 18}px) scale(${lerp(0.97, 1, kv)})`

  // 透镜：沿一条轻微下弯的弧线滑过横条，慢进慢出（sine）
  const lensT = clamp((t - B.lens) / 1.25)
  const ls = S.lensSize
  const cardX = L.cx - L.cardW / 2
  const lx = lerp(cardX - ls * 0.35, cardX + L.cardW - ls * 0.65, sine(lensT))
  const ly = topB + (P ? 210 : 170) + sine(lensT) * (P ? 200 : 170)
  const lensIn = fade(t, B.lens - 0.15, 0.3) * (1 - fade(t, B.lens + 1.2, 0.3))
  put(S.lens, { x: lx, y: ly, o: lensIn, s: lerp(0.85, 1, sp(t, B.lens - 0.15)) })

  // 第三屏：月报
  const inC = toReport
  const endK = sp(t, B.end, 0.6, 1)
  const shiftC = (1 - inC) * pushX
  const showC = fade(t, B['tab-report'] + 0.05, 0.35) * (1 - fade(t, B.end, 0.4))
  const topC = P ? 400 : 70
  const tilt = Math.sin(clamp((t - B['tab-report'] - 0.3) / 1.2) * Math.PI) // 一次轻微的左右倾斜
  const repBase = P ? 1 : 0.86
  S.report.style.transformOrigin = '50% 0'
  put(S.report, { x: shiftC, y: topC - endK * 40, o: showC, s: repBase * lerp(1, 0.94, endK), ry: tilt * 9, rx: -tilt * 3 })
  S.sheen.style.background = `linear-gradient(115deg, transparent 30%, rgb(255 255 255 / 0.4) ${44 + tilt * 22}%, transparent ${60 + tilt * 22}%)`
  const repP = sp(t, B['tab-report'] + 0.2, 0.9, 1)
  S.repTotal.textContent = money(254 * repP)

  // tab 栏：第一屏出现，选中胶囊沿弹簧滑动；落版前收走
  const tabIn = sp(t, B.cards + 0.15)
  const tabOut = sp(t, B.end - 0.1, 0.5, 1)
  put(S.tabs, { x: 0, y: L.tabY + (1 - tabIn) * 140 + tabOut * 200, o: fade(t, B.cards + 0.15, 0.3) * (1 - fade(t, B.end - 0.1, 0.3)) })
  const slot = lerp(0, 1, sp(t, B['tab-compare'])) + lerp(0, 1, sp(t, B['tab-report']))
  const pillW = (680 - 20) / 4
  S.tabPill.style.left = 10 + slot * pillW + 'px'
  S.tabPill.style.width = pillW + 'px'
  const active = t < B['tab-compare'] ? 0 : t < B['tab-report'] ? 1 : 2
  S.tabItems.forEach((e, i) => (e.style.color = i === active ? 'var(--accent)' : 'var(--label-2)'))

  // 落版
  const kl = sp(t, B.end + 0.1)
  const logoY = P ? H / 2 - 300 : H / 2 - 250
  put(S.logo, { x: 0, y: logoY + (1 - kl) * 26, o: fade(t, B.end + 0.1, 0.45), s: lerp(0.97, 1, kl) })
  const kt = sp(t, B.end + 0.35)
  // 最后一秒轻微呼吸，画面不死
  const breathe = 1 + Math.sin(clamp(t - B.end - 0.6, 0, 9) * 2.2) * 0.004
  S.logo.style.transform += ` scale(${breathe})`
  put(S.tag, { x: 0, y: logoY + (P ? 250 : 255) + (1 - kt) * 14, o: fade(t, B.end + 0.35, 0.45) })
  S.factCards.forEach((e, i) => {
    const k = sp(t, B.end + 0.5 + i * 0.08)
    e.style.opacity = fade(t, B.end + 0.5 + i * 0.08, 0.35)
    e.style.transform = `translateY(${(1 - k) * 22}px) scale(${lerp(0.94, 1, k)})`
  })
  put(S.factsRow, { x: 0, y: logoY + (P ? 360 : 345) })
}

// ---------- 启动 ----------
window.__ready = (async () => {
  build()
  initBg()
  await document.fonts.load('650 40px "TKF Sans"')
  await document.fonts.ready
  render(0)
})()
window.renderAt = (t) => render(t)

const fixed = Q.get('t')
if (fixed != null) {
  window.__ready.then(() => render(parseFloat(fixed)))
} else if (!Q.has('capture')) {
  // 预览：实时循环播放
  window.__ready.then(() => {
    const t0 = performance.now()
    const loop = (now) => {
      render(((now - t0) / 1000) % (DUR + 0.8))
      requestAnimationFrame(loop)
    }
    requestAnimationFrame(loop)
  })
}

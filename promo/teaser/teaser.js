/*
 * TOKENFIELD 22-second teaser — "订阅黑洞"
 * 1080×1350 @ 30fps  |  programmatic, no external video assets
 *
 * Time-map:
 *  0–2   s  Close-up bill, rapid pull-back, BLACK HOLE EDGE REVEAL
 *  2–7   s  Off-axis gravity ring forms; bills spiral in at varied depths/speeds
 *  7–11  s  Camera grazes ring; ring stretches to arc; CUT TO QUIET
 *  11–16 s  Circle→product shape match; Tokenfield UI reveal (spend + report glimpse)
 *  16–22 s  Light/lavender product atmosphere; end card
 */

/* ─── globals ────────────────────────────────────────────────────────────── */
const W = 1080, H = 1350, FPS = 30, DUR = 22
const Q = new URLSearchParams(location.search)
const FRAME_MODE = Q.has('capture')   // headless renderer sets ?capture=1

/* ─── math helpers ──────────────────────────────────────────────────────── */
const pi2 = Math.PI * 2
const clamp = (x, a=0, b=1) => Math.min(b, Math.max(a, x))
const lerp  = (a, b, k) => a + (b - a) * k
const easio = (x) => 1 - Math.pow(1 - clamp(x), 3)
const easia = (x) => Math.pow(clamp(x), 2)
const smooth = (a, b, k) => lerp(a, b, easio(clamp(k)))

/* spring: damped harmonic oscillator analytic */
function spring(t, r=0.55, z=0.82) {
  if (t <= 0) return 0; if (t > 3) return 1
  const w0=pi2/r, wd=w0*Math.sqrt(1-z*z)
  return 1 - Math.exp(-z*w0*t)*(Math.cos(wd*t)+z*w0/wd*Math.sin(wd*t))
}
function sp(t, t0, r=0.55, z=0.82) { return spring(t - t0, r, z) }
function fade(t, t0, d=0.35) { return easio((t - t0) / d) }
function fadeOut(t, t1, d=0.3) { return 1 - easio((t - t1) / d) }
function life(t, t0, t1, di=0.32, do_=0.3) {
  if (t < t0) return 0
  if (t1 != null && t >= t1) return fadeOut(t, t1, do_)
  return fade(t, t0, di)
}

/* ─── canvas & GL ───────────────────────────────────────────────────────── */
const cv  = document.getElementById('bg3d')
const gl  = cv.getContext('webgl', { preserveDrawingBuffer: true, antialias: true, alpha: false })
const ui  = document.getElementById('ui')

function mkShader(type, src) {
  const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s)
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) console.error(gl.getShaderInfoLog(s))
  return s
}
function mkProg(vs, fs) {
  const p = gl.createProgram()
  gl.attachShader(p, mkShader(gl.VERTEX_SHADER, vs))
  gl.attachShader(p, mkShader(gl.FRAGMENT_SHADER, fs))
  gl.linkProgram(p); return p
}

/* ─── fullscreen quad ───────────────────────────────────────────────────── */
const quadBuf = gl.createBuffer()
gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf)
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW)

/* ─── BACKGROUND (black + gravity ring) ─────────────────────────────────── */
const bgProg = mkProg(
  `attribute vec2 p; void main(){gl_Position=vec4(p,0,1);}`,
  `precision highp float;
  uniform vec2  res;
  uniform float t;          // scene time 0–22
  uniform vec2  ringC;      // ring center in NDC
  uniform float ringR;      // ring radius (0-1 of shorter screen side)
  uniform float ringW;      // ring thickness
  uniform float ringStr;    // brightness
  uniform float diskStr;    // accretion disk brightness
  uniform float lensStr;    // gravitational lensing distortion
  uniform float vignette;

  float sdRing(vec2 uv, vec2 c, float r, float w) {
    return abs(length(uv - c) - r) - w * 0.5;
  }
  // Physically-inspired lensing: inward deflection near the ring
  float schwarzschild(float r, float rs) {
    return rs / (r * r);
  }

  void main() {
    vec2 uv = (gl_FragCoord.xy / res) * 2.0 - 1.0;
    uv.x *= res.x / res.y;  // aspect correct

    vec2 rC = ringC; rC.x *= res.x / res.y;
    float aspect = res.x / res.y;

    // gravitational lens displacement
    vec2 delta = uv - rC;
    float dist = length(delta);
    float lens = lensStr * schwarzschild(max(dist, 0.06), ringR * 0.55);
    vec2 uvL = uv - normalize(delta) * lens;

    // background: deep black with very subtle warm gradient
    float bgGrad = 0.005 + 0.003 * (1.0 - uvL.y * 0.3);
    vec3 col = vec3(bgGrad * 0.5, bgGrad * 0.42, bgGrad * 0.35);

    // accretion disk
    vec2 dDelta = uvL - rC;
    // Ellipse: 2.0 squish = ~60deg tilt, clearly visible as ellipse
    vec2 dDeltaE = vec2(dDelta.x, dDelta.y * 2.0);
    float dDist  = length(dDeltaE);
    float angle  = atan(dDelta.y, dDelta.x);

    // Use TWO separate widths: thin ring edge + wide disk glow
    float thinW = max(ringW * 0.55, 0.022);  // crisp but visible
    float wideW = max(ringW * 2.5, 0.12);   // broad warm disk halo

    float diskD = abs(dDist - ringR);

    // Wide diffuse disk glow (warm orange, Doppler-modulated)
    float doppler = 0.4 + 0.6 * pow(max(0.0, cos(angle + 0.85)), 1.5);
    float shadow  = smoothstep(-0.04, 0.10, dDelta.y);
    float diskGlow = exp(-diskD * diskD / (wideW * wideW));
    col += diskStr * diskGlow * doppler * shadow * vec3(1.0, 0.6, 0.22);

    // Thin bright ring edge — the sharp arc
    float ringEdge = exp(-diskD * diskD / (thinW * thinW));
    col += ringStr * ringEdge * vec3(1.0, 0.85, 0.55);
    col += ringStr * 0.6 * ringEdge * ringEdge * vec3(1.0, 0.6, 0.25);

    // Photon sphere (innermost bright arc, slightly inside ring)
    float pDist = abs(dDist - ringR * 0.70);
    float photon = exp(-pDist * pDist / (thinW * thinW * 0.4));
    col += ringStr * 0.45 * photon * vec3(1.0, 0.92, 0.72);

    // Event horizon — black center
    float horizonD = length(dDeltaE) / ringR;
    float horizon  = smoothstep(0.52, 0.68, horizonD);
    col *= horizon;

    // outer vignette (no extra halo — keeps background clean and dark)
    col *= 1.0 - vignette * pow(length(uv) * 0.52, 2.2);

    // Simple gamma 2.2 — preserves orange hue
    col = pow(clamp(col, 0.0, 1.0), vec3(0.45));
    gl_FragColor = vec4(col, 1.0);
  }`
)

const uBG = (n) => gl.getUniformLocation(bgProg, n)

/* ─── ACCRETION PAPER CURL (on the bill canvas-2D) ─────────────────────── */
const billCanvas = document.createElement('canvas')
billCanvas.width = 680; billCanvas.height = 900
const bc = billCanvas.getContext('2d')

/* ─── BILLS DATA ─────────────────────────────────────────────────────────── */
const BILLS = [
  { name: 'Claude Pro', label: '月费订阅', amount: '¥142', color: '#d97757', orbit: 0.52, phase: 0.0,  depth: 0.55, speed: 0.45, w: 280, h: 175, startT: 1.2 },
  { name: 'ChatGPT Plus', label: '月费订阅', amount: '¥142', color: '#10a37f', orbit: 0.68, phase: 2.1, depth: 0.78, speed: 0.38, w: 230, h: 148, startT: 1.8 },
  { name: 'DeepSeek API', label: '按量付费', amount: '¥37', color: '#4d6bfe', orbit: 0.38, phase: 3.7, depth: 0.28, speed: 0.88, w: 210, h: 130, startT: 2.8 },
  { name: 'Kimi Plus', label: '月费订阅', amount: '¥99', color: '#3b4a6b', orbit: 0.68, phase: 1.0, depth: 0.88, speed: 0.35, w: 200, h: 130, startT: 3.2 },
  { name: '中转站余额', label: '充值', amount: '¥200', color: '#8e7cf0', orbit: 0.30, phase: 5.0, depth: 0.20, speed: 0.95, w: 190, h: 120, startT: 3.6 },
  { name: 'Gemini Pro', label: '月费订阅', amount: '¥142', color: '#4285f4', orbit: 0.55, phase: 4.3, depth: 0.65, speed: 0.48, w: 210, h: 135, startT: 2.6 },
]

/* ─── DOM bill elements ─────────────────────────────────────────────────── */
const billEls = BILLS.map((b) => {
  const d = document.createElement('div')
  d.className = 'bill abs'
  d.style.width  = b.w + 'px'
  d.style.height = b.h + 'px'
  d.innerHTML = `
    <div class="bill-label">${b.label} <span class="demoTag">演示数据</span></div>
    <div class="bill-name">${b.name}</div>
    <div class="bill-amount">${b.amount}<span style="font-size:14px;color:#888;margin-left:4px">/月</span></div>
    <div class="bill-line" style="background:${b.color};opacity:0.5"></div>
    <div class="bill-sub">2026年10月 · 自动续费</div>`
  d.style.opacity = '0'
  ui.appendChild(d)
  return d
})

/* close-up bill (scene 0-2) */
const closeBill = (() => {
  const d = document.createElement('div')
  d.className = 'bill abs'
  d.style.width  = '920px'
  d.style.height = '620px'
  d.innerHTML = `
    <div class="bill-label" style="font-size:16px;margin-top:24px">AI 月度账单 <span class="demoTag">演示数据</span></div>
    <div class="bill-name" style="font-size:28px;margin-top:12px">Claude Pro</div>
    <div class="bill-amount" style="font-size:72px;margin-top:8px">¥142<span style="font-size:22px;color:#888;margin-left:6px">/月</span></div>
    <div class="bill-line" style="background:#d97757;height:3px;margin-top:16px"></div>
    <div class="bill-sub" style="font-size:18px;margin-top:16px;color:#555">2026年10月 · 下次续费 10月31日</div>
    <div class="bill-sub" style="font-size:14px;margin-top:8px;color:#888">额度重置：每 5 小时</div>`
  d.style.opacity = '0'
  d.style.left = (W/2 - 460) + 'px'
  d.style.top  = (H/2 - 310) + 'px'
  d.style.transformOrigin = '50% 50%'
  ui.appendChild(d)
  return d
})()

/* ─── text overlays ─────────────────────────────────────────────────────── */
function makeText(html, style = {}) {
  const d = document.createElement('div')
  d.className = 'abs'
  d.innerHTML = html
  d.style.opacity = '0'
  d.style.left = '0'; d.style.width = W + 'px'; d.style.textAlign = 'center'
  Object.assign(d.style, style)
  ui.appendChild(d)
  return d
}

const txtQ1 = makeText(
  `<span style="font-size:88px;font-weight:800;line-height:1.1;letter-spacing:-0.04em;color:#fff;display:block;padding:0 80px">你的 AI</span>
   <span style="font-size:88px;font-weight:800;line-height:1.1;letter-spacing:-0.04em;color:#ff9a40;display:block;padding:0 80px">每个月吃掉多少钱？</span>`,
  { top: (H * 0.07) + 'px' }
)
const txtQ2 = makeText(
  `<span style="font-size:60px;font-weight:700;letter-spacing:-0.02em;color:#f5f0e8;display:block;padding:0 80px;line-height:1.2">钱花在哪</span>
   <span style="font-size:60px;font-weight:700;letter-spacing:-0.02em;color:#ff9a40;display:block;padding:0 80px;line-height:1.2">总得看清。</span>`,
  { top: (H * 0.72) + 'px' }
)

const productUI = (() => {
  const d = document.createElement('div')
  d.className = 'abs'
  d.style.cssText = `
    left:80px; top:${H*0.38}px; width:${W-160}px; border-radius:32px; padding:40px 44px;
    background:rgba(241,238,255,0.96); backdrop-filter:blur(36px) saturate(180%); opacity:0;
    box-shadow:0 40px 100px rgba(80,60,180,0.18),0 2px 8px rgba(80,60,180,0.1);`
  d.innerHTML = `
    <div style="font-size:13px;font-weight:600;letter-spacing:0.08em;color:#8b7cf0;text-transform:uppercase;margin-bottom:10px">本月花费 <span style="font-size:9px;background:rgba(0,0,0,0.12);border-radius:3px;padding:1px 4px;color:#6b5fcc;vertical-align:middle">演示数据</span></div>
    <div style="font-size:100px;font-weight:800;letter-spacing:-0.05em;color:#1a1430;line-height:0.95">¥<span>420</span></div>
    <div style="font-size:20px;color:#5c5470;margin-top:8px">平均每天 ¥14 · 3 个 AI 服务</div>
    <div style="margin-top:28px;height:12px;border-radius:99px;overflow:hidden;display:flex;gap:3px">
      <div style="flex:142;background:#d97757;border-radius:99px"></div>
      <div style="flex:100;background:#8e7cf0;border-radius:99px"></div>
      <div style="flex:37;background:#4d6bfe;border-radius:99px"></div>
    </div>
    <div style="margin-top:14px;display:flex;gap:24px;font-size:16px;color:#5c5470">
      <span>🟠 Claude Pro ¥142</span>
      <span>🟣 中转站 ¥100</span>
      <span>🔵 DeepSeek ¥37</span>
    </div>`
  ui.appendChild(d)
  return d
})()

const endCard = (() => {
  const d = document.createElement('div')
  d.className = 'abs'
  d.style.cssText = `left:0;top:0;width:1080px;height:1350px;opacity:0;
    background:linear-gradient(170deg, #ebe7ff 0%, #f4f0ff 35%, #fff0eb 70%, #ffe8e0 100%);
    display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0`
  d.innerHTML = `
    <div style="font-size:28px;font-weight:600;letter-spacing:0.12em;color:#8b7cf0;text-transform:uppercase;margin-bottom:20px">正在打磨</div>
    <div style="font-size:108px;font-weight:800;letter-spacing:-0.05em;color:#15102a;line-height:0.95">Tokenfield</div>
    <div style="font-size:32px;font-weight:600;letter-spacing:-0.01em;color:#2d1f60;margin-top:14px">额度终端</div>
    <div style="width:80px;height:3px;background:linear-gradient(90deg,#8b7cf0,#d97757);border-radius:99px;margin:18px auto"></div>
    <div style="width:440px;border-radius:22px;overflow:hidden;box-shadow:0 16px 50px rgba(80,40,180,0.22);margin:0 auto"><img src="/shots/v3/check-home.png" style="width:100%;display:block" onerror="this.style.display='none'" /></div>
    <div style="font-size:24px;color:#5c5470;text-align:center;padding:0 100px;line-height:1.6;max-width:800px">我正在打磨的 AI 花费与额度工具<br>让每一笔订阅都看得见</div>
    <div style="margin-top:44px;font-size:30px;font-weight:700;color:#8b7cf0">关注 @Lysandra_zyq</div>
    <div style="font-size:22px;color:#8b7cf0;margin-top:8px;opacity:0.7">持续更新</div>
    <div style="font-size:16px;color:#9c8fcc;margin-top:24px;letter-spacing:0.02em">tokenfield.vercel.app</div>`
  ui.appendChild(d)
  return d
})()

/* ─── AUDIO: procedural sound cues ─────────────────────────────────────── */
let audioCtx = null
function initAudio() {
  if (FRAME_MODE) return
  try { audioCtx = new AudioContext() } catch(e) {}
}

function playTone(freq, type, dur, t0, vol=0.18) {
  if (!audioCtx) return
  const now = audioCtx.currentTime
  const osc = audioCtx.createOscillator()
  const g   = audioCtx.createGain()
  osc.type = type; osc.frequency.setValueAtTime(freq, now + t0)
  g.gain.setValueAtTime(0, now + t0)
  g.gain.linearRampToValueAtTime(vol, now + t0 + 0.08)
  g.gain.exponentialRampToValueAtTime(0.001, now + t0 + dur)
  osc.connect(g); g.connect(audioCtx.destination)
  osc.start(now + t0); osc.stop(now + t0 + dur)
}

function playPaperRustle(t0) {
  if (!audioCtx) return
  const now = audioCtx.currentTime + t0
  const buf = audioCtx.createBuffer(1, audioCtx.sampleRate * 0.35, audioCtx.sampleRate)
  const d = buf.getChannelData(0)
  for (let i = 0; i < d.length; i++) {
    d[i] = (Math.random() * 2 - 1) * Math.exp(-i / (d.length * 0.4)) * 0.6
  }
  const src = audioCtx.createBufferSource()
  const f = audioCtx.createBiquadFilter()
  f.type = 'bandpass'; f.frequency.value = 3200; f.Q.value = 1.2
  const g = audioCtx.createGain()
  g.gain.setValueAtTime(0.22, now)
  g.gain.exponentialRampToValueAtTime(0.001, now + 0.35)
  src.buffer = buf; src.connect(f); f.connect(g); g.connect(audioCtx.destination)
  src.start(now)
}

function playGravityLFO(startT, dur) {
  if (!audioCtx) return
  const now = audioCtx.currentTime + startT
  const osc = audioCtx.createOscillator()
  const lfo = audioCtx.createOscillator()
  const lfoG = audioCtx.createGain()
  const g   = audioCtx.createGain()
  osc.type = 'sine'; osc.frequency.setValueAtTime(48, now)
  osc.frequency.linearRampToValueAtTime(38, now + dur)
  lfo.type = 'sine'; lfo.frequency.value = 0.7
  lfoG.gain.value = 4
  lfo.connect(lfoG); lfoG.connect(osc.frequency)
  g.gain.setValueAtTime(0, now)
  g.gain.linearRampToValueAtTime(0.12, now + 0.8)
  g.gain.linearRampToValueAtTime(0.1, now + dur - 0.6)
  g.gain.linearRampToValueAtTime(0, now + dur)
  osc.connect(g); g.connect(audioCtx.destination)
  lfo.start(now); osc.start(now); osc.stop(now + dur); lfo.stop(now + dur)
}

function scheduleAudio() {
  if (!audioCtx) return
  playPaperRustle(0.2)
  playTone(180, 'sawtooth', 0.6, 0.8, 0.06)
  playGravityLFO(1.8, 9.0)
  playPaperRustle(2.5)
  playPaperRustle(3.1)
  playPaperRustle(3.7)
  playTone(240, 'triangle', 0.5, 8.8, 0.1)   // quiet cue
  playTone(110, 'sine', 1.2, 10.2, 0.08)
  // reveal chime
  playTone(528, 'sine', 0.8, 11.2, 0.14)
  playTone(660, 'sine', 0.6, 11.35, 0.1)
  playTone(792, 'sine', 0.5, 11.55, 0.07)
  // end swell
  playTone(65, 'sine', 4.5, 16.2, 0.12)
  playTone(98, 'sine', 3.0, 16.5, 0.07)
}

/* ─── MAIN RENDER LOOP ──────────────────────────────────────────────────── */
let started = false, t0Real = 0

function render(tRaw) {
  const t = clamp(tRaw, 0, DUR)

  /* scene parameters */
  const ringCX = lerp(0.0, -0.08, clamp((t - 2) / 4))      // slight off-axis
  const ringCY = lerp(-0.09, 0.07, clamp((t - 2) / 5))
  const ringRadius = lerp(0.0, 0.85, Math.pow(clamp((t - 1.2) / 1.2), 0.6))
  const sweepMod = 1 + 1.4 * Math.pow(clamp((t - 7.2) / 1.2), 0.6) * Math.max(0, 1 - (t - 9.0) / 1.2)
  const ringW = lerp(0.0, 0.048, clamp((t - 1.4) / 1.0)) * lerp(1, 1.5, clamp((t - 7) / 1.5)) * sweepMod
  const ringStr  = lerp(0, 3.5, clamp((t - 1.5) / 1.0)) * lerp(1, 0, clamp((t - 9.5) / 1.8))
  const diskStr  = lerp(0, 2.2, clamp((t - 2) / 1.5)) * lerp(1, 0, clamp((t - 9) / 2.0))
  const lensStr  = lerp(0, 0.055, clamp((t - 2.5) / 2.0)) * lerp(1, 0, clamp((t - 9) / 2.0))
  const vig      = lerp(0.3, 1.1, clamp((t - 1) / 2))

  /* background fade to light at end */
  const prodFade = clamp((t - 15.5) / 1.8)

  /* draw GL background */
  gl.useProgram(bgProg)
  const posA = gl.getAttribLocation(bgProg, 'p')
  gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf)
  gl.enableVertexAttribArray(posA)
  gl.vertexAttribPointer(posA, 2, gl.FLOAT, false, 0, 0)

  gl.uniform2f(uBG('res'), W, H)
  gl.uniform1f(uBG('t'), t)
  gl.uniform2f(uBG('ringC'), ringCX, ringCY)
  gl.uniform1f(uBG('ringR'), ringRadius)
  gl.uniform1f(uBG('ringW'), ringW)
  gl.uniform1f(uBG('ringStr'), ringStr)
  gl.uniform1f(uBG('diskStr'), diskStr)
  gl.uniform1f(uBG('lensStr'), lensStr)
  gl.uniform1f(uBG('vignette'), vig)

  gl.clearColor(0, 0, 0, 1)
  gl.clear(gl.COLOR_BUFFER_BIT)
  gl.drawArrays(gl.TRIANGLES, 0, 3)

  /* ── close-up bill (0–2s) ── */
  const closeAlpha = life(t, 0.05, 2.2)
  const closeScale = lerp(4.2, 0.48, sp(t, 0.05, 0.65, 0.88))
  const closeCurl  = Math.max(0, t - 1.4) * 30   // curl degrees
  closeBill.style.opacity = closeAlpha
  closeBill.style.transform = `scale(${closeScale}) rotate(${closeCurl * 0.3}deg) perspective(1200px) rotateX(${closeCurl * 0.6}deg)`

  /* ── orbiting bills (2–11s) ── */
  const ringCXpx = W/2 + ringCX * H * 0.5
  const ringCYpx = H/2 - ringCY * H * 0.5
  const ringRpx  = ringRadius * H * 0.5

  BILLS.forEach((b, i) => {
    const el = billEls[i]
    const age = t - b.startT
    if (age < 0) { el.style.opacity = '0'; return }

    const suckedFrac = clamp((t - 6.5) / 3.5)
    const effectiveOrbit = b.orbit * lerp(1, 0.08, suckedFrac * suckedFrac)
    const kepler = b.speed * Math.pow(Math.max(effectiveOrbit, 0.04) / 0.55, -1.5) * 0.22
    const angle = (t * kepler + b.phase) % (pi2)
    const radius = effectiveOrbit * ringRpx * 1.15

    /* depth (z) modulates size + vertical offset — perspective cue */
    const depthScale = lerp(0.14, 1.6, b.depth)
    const depthY     = lerp(90, -90, b.depth)

    const cx = ringCXpx + Math.cos(angle) * radius
    // Orbit in the ring plane: Y squished to 0.5 matches the 2.0x vertical squish
    const cy = ringCYpx + Math.sin(angle) * radius * 0.5 + depthY

    /* tilt toward black hole center */
    const toCenter = Math.atan2(ringCYpx - cy, ringCXpx - cx)
    const tiltDeg  = lerp(12, 55, 1 - b.orbit)

    const suckScale = lerp(1.0, 0.05, Math.pow(clamp((t - 6.5) / 3.5), 2))
    const alpha = life(t, b.startT, 10.5) * suckScale
    el.style.opacity  = alpha
    el.style.transform = `
      translate(${cx - b.w/2}px, ${cy - b.h/2}px)
      scale(${depthScale * suckScale})
      perspective(900px)
      rotateX(60deg)
      rotateY(${(b.depth * 50 - 25).toFixed(1)}deg)
      rotateZ(${((angle * 180 / Math.PI) * 0.1 + i * 7).toFixed(1)}deg)
    `
    el.style.zIndex = Math.round(b.depth * 10)
  })

  /* ── txt: 「你的AI…」(0.5–3.2s) ── */
  txtQ1.style.opacity = life(t, 0.5, 3.2, 0.4, 0.5)
  txtQ1.style.transform = `translateY(${lerp(30, 0, sp(t, 0.5)) * fadeOut(t, 2.8)}px)`

  /* ── txt: 「钱花在哪」(8.2–11.2s) ── */
  txtQ2.style.opacity = life(t, 8.2, 11.0, 0.5, 0.6)
  txtQ2.style.transform = `translateY(${lerp(24, 0, sp(t, 8.2))}px)`

  /* ── product UI (11.5–16s) ── */
  productUI.style.opacity = life(t, 11.5, 16.0, 0.6, 0.8)
  productUI.style.transform = `
    translateY(${lerp(30, 0, sp(t, 11.5))}px)
    scale(${lerp(0.96, 1, sp(t, 11.5))})
  `

  /* ── end card (16–22s) ── */
  endCard.style.opacity = life(t, 16.0, null, 0.9)
  endCard.style.transform = `scale(${lerp(1.012, 1, sp(t, 16.0))})`
}

/* ─── boot ─────────────────────────────────────────────────────────────── */
window.__ready = (async () => {
  await document.fonts.load('800 80px "TKF"')
  await document.fonts.ready
  render(0)
})()

window.renderAt = (t) => render(t)

if (!FRAME_MODE) {
  window.__ready.then(() => {
    initAudio()
    const onClick = () => {
      if (!started) { started = true; t0Real = performance.now(); scheduleAudio() }
    }
    document.addEventListener('pointerdown', onClick, { once: true })

    const loop = (now) => {
      const t = started ? Math.min((now - t0Real) / 1000, DUR + 0.5) : 0
      render(t)
      requestAnimationFrame(loop)
    }
    requestAnimationFrame(loop)
  })
}

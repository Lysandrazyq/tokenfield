/**
 * 宣传片配音：全程序合成，零版权风险，无需外部采样。
 * 输出：promo/out/audio.wav（48 kHz / 16-bit stereo）
 *
 * 音效设计（匹配 cues.js 里的节拍）：
 *  tick   → 短促 sine 音（256 Hz，15 ms），有轻微混响尾巴
 *  rise   → 柔和 chord 上扬（根音 + 三度 + 五度，80 ms），代表内容升起
 *  switch → 两个音相错 10 ms（tab 切换感），140 Hz → 210 Hz
 *  glide  → 长而柔的扫频（180→340 Hz，780 ms），代表透镜滑过
 *  chime  → 三音和弦敲击（清脆 sin，有指数衰减），代表结论出现
 *  swell  → 低频 pad 渐入（多谐波，600 ms），代表落版
 *
 * 背景：极轻的 ambient pad，整片都在，代表电子质感。
 */
import { writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import './cues.js'

const CUES = globalThis.CUES
const SR = 48000
const DUR = CUES.duration
const TOTAL = Math.ceil(SR * DUR)
const here = dirname(fileURLToPath(import.meta.url))

// ——— 工具 ———
const pi2 = 2 * Math.PI
/** 线性包络 [t0, t1] 内从 0→1→0（梯形） */
const env = (s, t0, attack, sustain, release) => {
  const t = s / SR - t0
  if (t < 0 || t > attack + sustain + release) return 0
  if (t < attack) return t / attack
  if (t < attack + sustain) return 1
  return 1 - (t - attack - sustain) / release
}
/** 指数衰减 */
const decay = (s, t0, tau) => {
  const t = s / SR - t0
  return t < 0 ? 0 : Math.exp(-t / tau)
}
/** 每帧 sin 振荡，按相位连续（避免 click） */
class Osc {
  constructor(freq, amp = 1) { this.freq = freq; this.amp = amp; this.phase = 0 }
  tick() { const v = Math.sin(this.phase) * this.amp; this.phase += pi2 * this.freq / SR; return v }
}
/** 简单数字 reverb：一排短延迟线（Schroeder allpass） */
class Reverb {
  constructor() {
    this.lines = [1307, 1637, 1867, 2053, 2333].map((d) => ({ buf: new Float32Array(d), idx: 0, g: 0.7 }))
  }
  process(x) {
    let out = x
    for (const l of this.lines) {
      const delayed = l.buf[l.idx]
      l.buf[l.idx] = out + delayed * l.g
      l.idx = (l.idx + 1) % l.buf.length
      out = delayed - l.g * l.buf[l.idx]
    }
    return out
  }
}
/** 短暂混响：只把尾音加进主信号，不替换 */
const verb = new Reverb()
const verbBuf = new Float32Array(TOTAL)
function addVerb(buf, t0, sig, wet = 0.18) {
  for (let s = 0; s < sig.length; s++) {
    const i = Math.round(t0 * SR) + s
    if (i >= 0 && i < buf.length) {
      const dry = sig[s]
      const r = verb.process(dry)
      buf[i] += dry + r * wet
    }
  }
}

// ——— 合成缓冲区 ———
const L = new Float32Array(TOTAL)
const R = new Float32Array(TOTAL)

// ——— 背景 ambient pad ———
// 四个谐波轻微相位调制（让声音「呼吸」），整片渐入再渐出
const pads = [65, 97.5, 130, 195].map((f, i) => ({ o: new Osc(f, [0.018, 0.011, 0.007, 0.004][i]), lfo: new Osc(0.23 + i * 0.07, 0.003) }))
for (let s = 0; s < TOTAL; s++) {
  const t = s / SR
  const fade = Math.min(1, t / 0.8) * Math.min(1, (DUR - t) / 0.6)
  let v = 0
  for (const { o, lfo } of pads) { o.freq += lfo.tick() * 0.05; v += o.tick() }
  L[s] += v * fade
  R[s] += v * fade * 0.98 // 轻微立体声宽度
}

// ——— 音效合成工具 ———
function makeTick(freq = 256, ms = 14) {
  const n = Math.ceil(SR * ms / 1000)
  const buf = new Float32Array(n)
  const o = new Osc(freq, 0.38)
  for (let s = 0; s < n; s++) buf[s] = o.tick() * decay(s, 0, ms / 1000 / 3.5)
  return buf
}
function makeRise(root = 220, ms = 90) {
  const n = Math.ceil(SR * ms / 1000)
  const buf = new Float32Array(n)
  const octs = [new Osc(root, 0.22), new Osc(root * 1.26, 0.14), new Osc(root * 1.5, 0.1)]
  for (let s = 0; s < n; s++) {
    const e = 1 - Math.pow(1 - s / n, 2)
    buf[s] = octs.reduce((acc, o) => acc + o.tick(), 0) * e * 0.7
  }
  return buf
}
function makeSwitch(f1 = 140, f2 = 210, ms = 180) {
  const n = Math.ceil(SR * ms / 1000)
  const buf = new Float32Array(n)
  const lag = Math.round(SR * 0.012) // 10 ms 错位
  const a = new Osc(f1, 0.28), b = new Osc(f2, 0.22)
  for (let s = 0; s < n; s++) {
    buf[s] = a.tick() * decay(s, 0, 0.055)
    if (s >= lag) buf[s] += b.tick() * decay(s - lag, 0, 0.04)
  }
  return buf
}
function makeGlide(f0 = 180, f1 = 340, ms = 780) {
  const n = Math.ceil(SR * ms / 1000)
  const buf = new Float32Array(n)
  let phase = 0
  for (let s = 0; s < n; s++) {
    const p = s / n
    const freq = f0 + (f1 - f0) * p * p // 非线性扫频（开始慢）
    const e = env(s * (DUR / n), 0, 0.12, 0.52, 0.14)
    buf[s] = Math.sin(phase) * e * 0.32
    phase += pi2 * freq / SR
  }
  return buf
}
function makeChime(ms = 260) {
  const n = Math.ceil(SR * ms / 1000)
  const buf = new Float32Array(n)
  const fs = [528, 660, 792, 1056]
  const os = fs.map((f, i) => new Osc(f, [0.28, 0.2, 0.14, 0.07][i]))
  for (let s = 0; s < n; s++) {
    const e = decay(s, 0, 0.065)
    buf[s] = os.reduce((acc, o) => acc + o.tick(), 0) * e
  }
  return buf
}
function makeSwell(ms = 700) {
  const n = Math.ceil(SR * ms / 1000)
  const buf = new Float32Array(n)
  const os = [55, 82.5, 110, 165].map((f, i) => new Osc(f, [0.24, 0.16, 0.1, 0.06][i]))
  for (let s = 0; s < n; s++) {
    const e = 1 - Math.exp(-s / (SR * 0.18))
    buf[s] = os.reduce((acc, o) => acc + o.tick(), 0) * e * 0.65
  }
  return buf
}

// ——— 按节拍放置音效 ———
const sounds = {
  tick: makeTick, rise: makeRise, switch: makeSwitch, glide: makeGlide, chime: makeChime, swell: makeSwell,
}
for (const beat of CUES.beats) {
  const fn = sounds[beat.sound]
  if (!fn) continue
  const sig = fn()
  addVerb(L, beat.t, sig, beat.sound === 'tick' ? 0.12 : 0.22)
  addVerb(R, beat.t, sig, beat.sound === 'tick' ? 0.1 : 0.2)
}
// tick 系列：轻微声像左右交替（tap 感）
let side = 1
for (const beat of CUES.beats.filter((b) => b.sound === 'tick')) {
  const i0 = Math.round(beat.t * SR)
  const sig = makeTick()
  for (let s = 0; s < sig.length; s++) {
    if (i0 + s < TOTAL) {
      L[i0 + s] += sig[s] * (side > 0 ? 1 : 0.6) * 0.45
      R[i0 + s] += sig[s] * (side < 0 ? 1 : 0.6) * 0.45
    }
  }
  side = -side
}

// ——— 软限幅（软膝 tanh）+ 归一化 ———
let peak = 0; for (let s = 0; s < TOTAL; s++) { if (Math.abs(L[s]) > peak) peak = Math.abs(L[s]); if (Math.abs(R[s]) > peak) peak = Math.abs(R[s]) }
const norm = peak > 0.001 ? 0.92 / peak : 1
for (let s = 0; s < TOTAL; s++) {
  L[s] = Math.tanh(L[s] * norm * 1.08)
  R[s] = Math.tanh(R[s] * norm * 1.08)
}

// ——— 写 WAV ———
const blockAlign = 4 // 16-bit stereo
const dataLen = TOTAL * blockAlign
const buf = Buffer.alloc(44 + dataLen)
buf.write('RIFF', 0)
buf.writeUInt32LE(36 + dataLen, 4)
buf.write('WAVEfmt ', 8)
buf.writeUInt32LE(16, 16)
buf.writeUInt16LE(1, 20)   // PCM
buf.writeUInt16LE(2, 22)   // channels
buf.writeUInt32LE(SR, 24)
buf.writeUInt32LE(SR * blockAlign, 28)
buf.writeUInt16LE(blockAlign, 32)
buf.writeUInt16LE(16, 34)
buf.write('data', 36)
buf.writeUInt32LE(dataLen, 40)
for (let s = 0; s < TOTAL; s++) {
  buf.writeInt16LE(Math.round(L[s] * 32767), 44 + s * 4)
  buf.writeInt16LE(Math.round(R[s] * 32767), 44 + s * 4 + 2)
}
const out = join(here, '..', 'promo', 'out', 'audio.wav')
writeFileSync(out, buf)
console.log(`audio → ${out}  peak=${peak.toFixed(3)}  ${TOTAL} samples`)

import { useEffect, useRef } from 'react'
import { useTheme } from '../lib/appearance'

const hex = (h: string) => [1, 3, 5].map((k) => parseInt(h.slice(k, k + 2), 16) / 255)

/**
 * 背景只是「玻璃后面的东西」：低饱和、慢、不抢戏。
 * 玻璃要有东西可折射才好看，所以留几团柔和的色块，但整体压得很淡。
 */
const PALETTES = {
  dark: { base: '#0a0b10', cols: ['#3b3a8f', '#1f3f7a', '#155e6e', '#4a2f80', '#1b4f55'], strength: 0.5, vig: 0.7 },
  light: { base: '#f2f3f7', cols: ['#d9dcfb', '#cfe3f7', '#d3f0ef', '#e7def8', '#f6e9d8'], strength: 0.9, vig: 0.97 },
}

// 极光底：4~5 个邻近色大光斑沿闭合贝塞尔路径缓慢漂移，在 shader 里叠成 mesh gradient，
// 最后叠一层噪点抖动防 banding。画布按 1/4 分辨率渲染再放大，本来就是模糊的，不影响观感，手机上也省电。

const VERT = `attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}`

const FRAG = `
precision highp float;
uniform vec2 res;
uniform float t;
uniform vec2 c[5];
uniform float r[5];
uniform vec3 base;
uniform vec3 cols[5];
// 光斑混合强度 / 暗角力度：深色下压暗四周，浅色下几乎不压
uniform float strength;
uniform float vig;
float hash(vec2 q){return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);}
void main(){
  vec2 uv = gl_FragCoord.xy / res;
  // 用短边做单位，竖屏手机上光斑不会糊满整屏
  vec2 span = res / min(res.x, res.y);
  vec2 q = uv * span;
  vec3 acc = vec3(0.0);
  float wsum = 0.0;
  for (int i = 0; i < 5; i++) {
    vec2 d = q - c[i] * span;
    float w = exp(-dot(d, d) / (r[i] * r[i]));
    acc += cols[i] * w;
    wsum += w;
  }
  // 色相按权重混合，亮度按总权重压一下，暗底亮斑
  vec3 hue = acc / max(wsum, 1e-4);
  float glow = 1.0 - exp(-wsum * 0.95);
  vec3 color = mix(base, hue, glow * strength);
  // 暗角
  float v = smoothstep(1.25, 0.25, length((uv - 0.5) * span / max(span.x, span.y) * 1.6));
  color *= mix(vig, 1.0, v);
  // 低分辨率画布放大后噪点会变成色块，这里只加极轻的抖动，主要的颗粒由全分辨率的 .grain 层负责
  color += (hash(gl_FragCoord.xy + fract(t) * 91.7) - 0.5) * 0.008;
  gl_FragColor = vec4(color, 1.0);
}
`

type V2 = [number, number]

/** 每个光斑一条闭合三次贝塞尔路径（4 段），周期 20~40 秒 */
const PATHS: { pts: V2[]; period: number; radius: number; phase: number }[] = [
  { pts: [[0.15, 0.80], [0.45, 0.95], [0.40, 0.55], [0.10, 0.50]], period: 34, radius: 0.46, phase: 0.0 },
  { pts: [[0.85, 0.85], [0.95, 0.55], [0.65, 0.60], [0.70, 0.95]], period: 28, radius: 0.42, phase: 0.3 },
  { pts: [[0.80, 0.20], [0.55, 0.05], [0.50, 0.35], [0.95, 0.40]], period: 38, radius: 0.40, phase: 0.6 },
  { pts: [[0.20, 0.15], [0.05, 0.40], [0.35, 0.35], [0.40, 0.05]], period: 24, radius: 0.38, phase: 0.15 },
  { pts: [[0.50, 0.50], [0.65, 0.30], [0.35, 0.25], [0.45, 0.70]], period: 40, radius: 0.30, phase: 0.8 },
]

function cubic(a: V2, b: V2, c: V2, d: V2, s: number): V2 {
  const u = 1 - s
  return [
    u * u * u * a[0] + 3 * u * u * s * b[0] + 3 * u * s * s * c[0] + s * s * s * d[0],
    u * u * u * a[1] + 3 * u * u * s * b[1] + 3 * u * s * s * c[1] + s * s * s * d[1],
  ]
}

/** 把 4 个锚点当成闭合 Catmull-Rom 曲线，转成贝塞尔分段求点，保证路径平滑无折角 */
export function blobAt(i: number, time: number): V2 {
  const { pts, period, phase } = PATHS[i]
  const n = pts.length
  const f = (((time / period + phase) % 1) + 1) % 1
  const seg = Math.floor(f * n)
  const s = f * n - seg
  const p0 = pts[(seg - 1 + n) % n], p1 = pts[seg], p2 = pts[(seg + 1) % n], p3 = pts[(seg + 2) % n]
  const b1: V2 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
  const b2: V2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
  return cubic(p1, b1, b2, p2, s)
}

export function blobRadius(i: number, time: number) {
  // 半径带一点呼吸
  return PATHS[i].radius * (1 + 0.08 * Math.sin((time / PATHS[i].period) * Math.PI * 2 * 2 + i))
}

export default function AuroraBackground({ scale = 0.25 }: { scale?: number }) {
  const ref = useRef<HTMLCanvasElement>(null)
  const theme = useTheme()

  useEffect(() => {
    const canvas = ref.current!
    const gl = canvas.getContext('webgl', { antialias: false, alpha: false, preserveDrawingBuffer: false })
    if (!gl) {
      canvas.style.background = 'var(--page)'
      return
    }
    const compile = (type: number, src: string) => {
      const s = gl.createShader(type)!
      gl.shaderSource(s, src)
      gl.compileShader(s)
      return s
    }
    const prog = gl.createProgram()!
    gl.attachShader(prog, compile(gl.VERTEX_SHADER, VERT))
    gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FRAG))
    gl.linkProgram(prog)
    gl.useProgram(prog)
    const buf = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, buf)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
    const loc = gl.getAttribLocation(prog, 'p')
    gl.enableVertexAttribArray(loc)
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0)
    const uRes = gl.getUniformLocation(prog, 'res')
    const uT = gl.getUniformLocation(prog, 't')
    const uC = gl.getUniformLocation(prog, 'c')
    const uR = gl.getUniformLocation(prog, 'r')
    const pal = PALETTES[theme]
    gl.uniform3fv(gl.getUniformLocation(prog, 'base'), hex(pal.base))
    gl.uniform3fv(gl.getUniformLocation(prog, 'cols'), pal.cols.flatMap(hex))
    gl.uniform1f(gl.getUniformLocation(prog, 'strength'), pal.strength)
    gl.uniform1f(gl.getUniformLocation(prog, 'vig'), pal.vig)

    const resize = () => {
      canvas.width = Math.max(64, Math.round(innerWidth * scale))
      canvas.height = Math.max(64, Math.round(innerHeight * scale))
      gl.viewport(0, 0, canvas.width, canvas.height)
    }
    resize()
    addEventListener('resize', resize)

    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
    // 从一个固定的偏移开始，首帧就有好看的构图
    const t0 = performance.now() - 12_000
    let raf = 0
    const draw = (now: number) => {
      const time = reduced ? 12 : (now - t0) / 2000
      const cs: number[] = [], rs: number[] = []
      for (let i = 0; i < PATHS.length; i++) {
        cs.push(...blobAt(i, time))
        rs.push(blobRadius(i, time))
      }
      gl.uniform2f(uRes, canvas.width, canvas.height)
      gl.uniform1f(uT, time)
      gl.uniform2fv(uC, cs)
      gl.uniform1fv(uR, rs)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
      if (!reduced && !document.hidden) raf = requestAnimationFrame(draw)
    }
    const onVis = () => {
      cancelAnimationFrame(raf)
      if (!document.hidden) raf = requestAnimationFrame(draw)
    }
    document.addEventListener('visibilitychange', onVis)
    raf = requestAnimationFrame(draw)
    return () => {
      cancelAnimationFrame(raf)
      removeEventListener('resize', resize)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [scale, theme])

  return (
    <canvas ref={ref} aria-hidden className="fixed inset-0 -z-10 h-full w-full [view-transition-name:backdrop]" />
  )
}

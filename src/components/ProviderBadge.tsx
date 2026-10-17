import { providerOf } from '../data/pricing'

/**
 * 服务商徽标：优先显示从官网抓取的真实 Logo，
 * 加载失败时降级为品牌色 + 首字母方块。
 *
 * 图标来源见 public/logos/_sources.txt 和 CREDITS.md。
 * 仅用于展示用户自己录入的订阅信息。
 */
const LOGO_FILES: Record<string, string> = {
  chatgpt:  '/logos/chatgpt.png',
  claude:   '/logos/claude.png',
  gemini:   '/logos/gemini.png',
  deepseek: '/logos/deepseek.png',
  kimi:     '/logos/kimi.png',
  glm:      '/logos/glm.png',
  qwen:     '/logos/qwen.svg',
  doubao:   '/logos/doubao.png',
  minimax:  '/logos/minimax.png',
}

export default function ProviderBadge({
  provider,
  name,
  size = 40,
  /** 强制字母降级，防止 html-to-image 跨域污染 canvas */
  fallback = false,
}: {
  provider: string
  name: string
  size?: number
  fallback?: boolean
}) {
  const { color } = providerOf(provider)
  const logoSrc = !fallback ? LOGO_FILES[provider] : undefined
  const r = size * 0.28

  const base: React.CSSProperties = {
    width: size, height: size, borderRadius: r, flexShrink: 0,
    background: `linear-gradient(160deg, color-mix(in oklab, ${color} 82%, white), ${color})`,
    boxShadow: `inset 0 0.5px 0 rgb(255 255 255 / 0.45), inset 0 0 0 0.5px rgb(0 0 0 / 0.08), 0 4px 12px -6px ${color}`,
  }

  if (!logoSrc) {
    return (
      <span
        aria-hidden
        className="smooth relative grid shrink-0 place-items-center font-semibold text-white"
        style={{ ...base, fontSize: size * 0.42 }}
      >
        {name.trim().slice(0, 1).toUpperCase() || '?'}
      </span>
    )
  }

  return (
    <span aria-hidden className="smooth relative shrink-0 block overflow-hidden" style={base}>
      <img
        src={logoSrc}
        alt={name}
        width={size}
        height={size}
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }}
        onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
      />
    </span>
  )
}

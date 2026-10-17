import { useEffect } from 'react'
import { Route, Routes, useLocation, useNavigate } from 'react-router-dom'
import { useStore } from './lib/store'
import { scheduleAll } from './lib/notify'
import { go, markBooted, TAB_ORDER } from './lib/transition'
import AuroraBackground from './components/AuroraBackground'
import LiquidGlass from './components/LiquidGlass'
import Home from './pages/Home'
import Edit from './pages/Edit'
import ExpiryEdit from './pages/ExpiryEdit'
import Card from './pages/Card'
import Settings from './pages/Settings'
import Compare from './pages/Compare'

const TABS = [
  { to: '/', label: '概览', icon: 'M4 5.5A1.5 1.5 0 0 1 5.5 4h4A1.5 1.5 0 0 1 11 5.5v5A1.5 1.5 0 0 1 9.5 12h-4A1.5 1.5 0 0 1 4 10.5v-5Zm9 0A1.5 1.5 0 0 1 14.5 4h4A1.5 1.5 0 0 1 20 5.5v2A1.5 1.5 0 0 1 18.5 9h-4A1.5 1.5 0 0 1 13 7.5v-2ZM4 15.5A1.5 1.5 0 0 1 5.5 14h4a1.5 1.5 0 0 1 1.5 1.5v3A1.5 1.5 0 0 1 9.5 20h-4A1.5 1.5 0 0 1 4 18.5v-3Zm9-3A1.5 1.5 0 0 1 14.5 11h4a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5h-4a1.5 1.5 0 0 1-1.5-1.5v-6Z' },
  { to: '/compare', label: '比价', icon: 'M5 20a1 1 0 0 1-1-1v-7a1 1 0 1 1 2 0v7a1 1 0 0 1-1 1Zm7 0a1 1 0 0 1-1-1V5a1 1 0 1 1 2 0v14a1 1 0 0 1-1 1Zm7 0a1 1 0 0 1-1-1v-4a1 1 0 1 1 2 0v4a1 1 0 0 1-1 1Z' },
  { to: '/card', label: '月报', icon: 'M7 3h10a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Zm1 5a1 1 0 0 0 0 2h8a1 1 0 1 0 0-2H8Zm0 4a1 1 0 1 0 0 2h5a1 1 0 1 0 0-2H8Z' },
  { to: '/settings', label: '设置', icon: 'M10.3 3.4a1.7 1.7 0 0 1 3.4 0l.1.6a7.4 7.4 0 0 1 1.7 1l.6-.2a1.7 1.7 0 0 1 2 .8 1.7 1.7 0 0 1-.4 2.1l-.4.4a7.6 7.6 0 0 1 0 2l.4.4a1.7 1.7 0 0 1-1.6 2.9l-.6-.2a7.4 7.4 0 0 1-1.7 1l-.1.6a1.7 1.7 0 0 1-3.4 0l-.1-.6a7.4 7.4 0 0 1-1.7-1l-.6.2a1.7 1.7 0 0 1-1.6-2.9l.4-.4a7.6 7.6 0 0 1 0-2l-.4-.4a1.7 1.7 0 0 1 1.6-2.9l.6.2a7.4 7.4 0 0 1 1.7-1l.1-.6ZM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z' },
] as const

/** 这些页面在宽屏下铺开成多栏 */
const WIDE = ['/', '/compare']

function TabIcon({ d }: { d: string }) {
  return (
    <svg viewBox="0 0 24 24" className="h-[22px] w-[22px]" fill="currentColor" aria-hidden>
      <path d={d} fillRule="evenodd" />
    </svg>
  )
}

export default function App() {
  const location = useLocation()
  const navigate = useNavigate()
  const { accounts, expiries, settings } = useStore()

  useEffect(markBooted, [])

  // 任何数据变动都重新排一遍提醒
  useEffect(() => {
    scheduleAll(accounts, expiries, settings).catch(console.error)
  }, [accounts, expiries, settings])

  useEffect(() => {
    window.scrollTo({ top: 0 })
  }, [location.pathname])

  const activeTab = TAB_ORDER.indexOf(location.pathname)
  const isTab = activeTab >= 0
  const toTab = (to: string) => (e: React.MouseEvent) => {
    e.preventDefault()
    if (to !== location.pathname) go(navigate, to, { from: location.pathname })
  }

  return (
    <>
      <AuroraBackground />

      {/* 宽屏：左侧导航栏（Apple 的侧边栏用更厚的材质，和内容层区分） */}
      <aside className="fixed inset-y-0 left-0 z-40 hidden w-64 p-3 lg:block [view-transition-name:sidebar]">
        <div className="card flex h-full flex-col p-3!">
          <div className="px-3 pb-6 pt-4">
            <div className="display text-[22px]">Tokenfield</div>
            <div className="text-[13px] text-label-2">额度终端</div>
          </div>
          <nav className="space-y-0.5">
            {TABS.map((t, k) => (
              <a
                key={t.to}
                href={`#${t.to}`}
                onClick={toTab(t.to)}
                aria-current={activeTab === k ? 'page' : undefined}
                className={`press flex items-center gap-3 rounded-[12px] px-3 py-2.5 text-[15px] smooth ${
                  activeTab === k ? 'bg-accent-soft font-medium text-accent' : 'text-label hover:bg-fill-2'
                }`}
              >
                <TabIcon d={t.icon} />
                {t.label}
              </a>
            ))}
          </nav>
          <p className="mt-auto px-3 pb-2 text-[12px] text-label-3">数据只存在这台设备上</p>
        </div>
      </aside>

      <main
        className={`mx-auto min-h-dvh px-4 pt-[env(safe-area-inset-top)] [view-transition-name:page] lg:pl-[17rem] lg:pr-8 lg:pb-10 ${
          WIDE.includes(location.pathname) ? 'max-w-lg lg:max-w-[1240px]' : 'max-w-lg lg:max-w-[calc(38rem+17rem)]'
        } ${isTab ? 'pb-32' : 'pb-10'}`}
      >
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/account/:id" element={<Edit />} />
          <Route path="/expiry/:id" element={<ExpiryEdit />} />
          <Route path="/card" element={<Card />} />
          <Route path="/compare" element={<Compare />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </main>

      {/* 手机：悬浮液态玻璃 tab 栏。选中指示是一颗沿同一条弹簧滑动的胶囊 */}
      <nav
        className={`fixed inset-x-0 bottom-0 z-40 flex justify-center px-6 pb-[calc(env(safe-area-inset-bottom)+14px)] [view-transition-name:tabbar] lg:hidden ${
          isTab ? '' : 'pointer-events-none'
        }`}
        style={{
          transform: isTab ? undefined : 'translateY(130%)',
          transition: 'transform var(--dur-spring) var(--ease-spring)',
        }}
      >
        <LiquidGlass radius={999} bezel={22} strength={44} className="grid w-full max-w-[340px] grid-cols-4 p-1.5">
          <span
            aria-hidden
            className="absolute top-1.5 bottom-1.5 rounded-full bg-fill"
            style={{
              left: `calc(6px + ${Math.max(0, activeTab)} * (100% - 12px) / ${TABS.length})`,
              width: `calc((100% - 12px) / ${TABS.length})`,
              opacity: isTab ? 1 : 0,
              transition: 'left var(--dur-spring) var(--ease-spring), opacity var(--dur-fade) var(--ease-out)',
            }}
          />
          {TABS.map((t, k) => (
            <a
              key={t.to}
              href={`#${t.to}`}
              onClick={toTab(t.to)}
              aria-current={activeTab === k ? 'page' : undefined}
              className={`press relative flex flex-col items-center gap-0.5 rounded-full py-1.5 text-[10px] font-medium transition-colors duration-200 ${
                activeTab === k ? 'text-accent' : 'text-label-2'
              }`}
            >
              <TabIcon d={t.icon} />
              {t.label}
            </a>
          ))}
        </LiquidGlass>
      </nav>
    </>
  )
}

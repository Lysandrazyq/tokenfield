// 开发自检：手机 + 电脑两种尺寸、浅色 + 深色，逐页截图；检查报错和 View Transition 是否触发
import puppeteer from 'puppeteer-core'
import { mkdirSync } from 'node:fs'
import { seed } from './seed.mjs'

const BASE = process.env.BASE || 'http://localhost:2839/'
const OUT = 'shots/v3'
mkdirSync(OUT, { recursive: true })
const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const errors = []
const page = await browser.newPage()
page.on('pageerror', (e) => errors.push(String(e)))
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))

const sizes = {
  phone: { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true },
  desktop: { width: 1440, height: 900, deviceScaleFactor: 1 },
}
await page.setViewport(sizes.phone)
await page.goto(BASE, { waitUntil: 'networkidle0' })
await seed(page)
await page.evaluate(() => localStorage.setItem('tkf-appearance', JSON.stringify({ theme: 'light', refraction: true })))

const shot = async (hash, name) => {
  await page.goto(BASE + hash, { waitUntil: 'networkidle0' })
  await page.reload({ waitUntil: 'networkidle0' })
  await new Promise((r) => setTimeout(r, 1800))
  await page.screenshot({ path: `${OUT}/${name}.png` })
}

for (const theme of ['light', 'dark']) {
  await page.evaluate((t) => localStorage.setItem('tkf-appearance', JSON.stringify({ theme: t, refraction: true })), theme)
  for (const [size, vp] of Object.entries(sizes)) {
    await page.setViewport(vp)
    for (const [hash, n] of [['#/', 'home'], ['#/compare', 'compare'], ['#/card', 'card'], ['#/settings', 'settings'], ['#/account/1', 'edit']]) {
      await shot(hash, `${size}-${theme}-${n}`)
    }
  }
}

// 转场：从概览点进 AI 卡片，转场中途截一帧
await page.setViewport(sizes.phone)
await page.evaluate(() => localStorage.setItem('tkf-appearance', JSON.stringify({ theme: 'light', refraction: true })))
await page.goto(BASE + '#/', { waitUntil: 'networkidle0' })
await page.reload({ waitUntil: 'networkidle0' })
await new Promise((r) => setTimeout(r, 1800))
const vt = await page.evaluate(() => 'startViewTransition' in document)
// 冷启动后立刻切页（用户说「初次打开切页会闪」的场景），连续抓帧找空白帧
// 新开一个页面：同一个 page 从桌面尺寸切回手机尺寸时，Chrome 会沿用旧的布局视口
await page.close()
const p2 = await browser.newPage()
p2.on('pageerror', (e) => errors.push(String(e)))
await p2.setViewport(sizes.phone)
await p2.goto(BASE + '#/', { waitUntil: 'domcontentloaded' })
await p2.waitForSelector('main h1')
console.log('viewport', await p2.evaluate(() => [innerWidth, getComputedStyle(document.querySelector('nav.fixed')).display]))
const cdp = await p2.createCDPSession()
const frames = []
cdp.on('Page.screencastFrame', async (f) => {
  frames.push(f.data)
  await cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId })
})
await cdp.send('Page.startScreencast', { format: 'png', everyNthFrame: 1, maxWidth: 390, maxHeight: 844 })
await new Promise((r) => setTimeout(r, 120))
await p2.click('nav.fixed a[href="#/compare"]')
await new Promise((r) => setTimeout(r, 1100))
await p2.click('nav.fixed a[href="#/"]')
await new Promise((r) => setTimeout(r, 400))
await p2.click('main a[href^="#/account/"]:not([href$="new"])')
await new Promise((r) => setTimeout(r, 1100))
await cdp.send('Page.stopScreencast')
const { writeFileSync } = await import('node:fs')
mkdirSync(`${OUT}/frames`, { recursive: true })
frames.forEach((d, k) => writeFileSync(`${OUT}/frames/f${String(k).padStart(3, '0')}.png`, Buffer.from(d, 'base64')))
console.log('frames', frames.length)
console.log('vt supported:', vt, 'url after click:', p2.url())
// 液态玻璃滤镜是否挂上
const lg = await p2.evaluate(() => {
  const nav = document.querySelector('nav .liquid')
  return nav ? getComputedStyle(nav).backdropFilter : 'no nav'
})
console.log('tabbar backdrop:', lg.slice(0, 80))
console.log('errors:', errors.length ? errors : 'none')
await browser.close()

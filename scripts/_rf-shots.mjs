import puppeteer from 'puppeteer-core'
import { seed } from './seed.mjs'
import { mkdir } from 'node:fs/promises'

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const page = await browser.newPage()
const errors = []
page.on('pageerror', e => errors.push(e.message))
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle0' })
await seed(page)
await mkdir('shots/v3', { recursive: true })

const pairs = [
  { hash: '#/', name: 'home', theme: 'dark' },
  { hash: '#/', name: 'home-light', theme: 'light' },
  { hash: '#/compare', name: 'compare', theme: 'dark' },
  { hash: '#/account/new', name: 'edit', theme: 'dark' },
  { hash: '#/settings', name: 'settings', theme: 'light' },
]

for (const { hash, name, theme } of pairs) {
  await page.evaluate((t) => localStorage.setItem('tkf-appearance', JSON.stringify({ theme: t, refraction: true })), theme)
  await page.goto(`http://localhost:5173/${hash}`, { waitUntil: 'networkidle0' })
  await page.reload({ waitUntil: 'networkidle0' })
  await new Promise(r => setTimeout(r, 1500))
  if (name === 'settings') {
    await page.evaluate(() => window.scrollTo(0, 300))
    await new Promise(r => setTimeout(r, 300))
  }
  await page.screenshot({ path: `shots/v3/rf-${name}.png` })
}

console.log('errors:', errors.length ? errors : 'none')
await browser.close()

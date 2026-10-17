// 开发自检：浅色 / 深色 × 融球范围，各截一张首页 + 设置页，检查报错
// 用法：先 npm run dev（并跑过一次 shots.mjs 写入示例数据），再 node scripts/theme-shots.mjs
import puppeteer from 'puppeteer-core'
import { mkdirSync } from 'node:fs'
import { seed } from './seed.mjs'

const BASE = '' + (process.env.BASE || 'http://localhost:2839/') + ''
const OUT = 'shots/theme'
mkdirSync(OUT, { recursive: true })

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
const errors = []
page.on('pageerror', (e) => errors.push(String(e)))
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))

await page.goto(BASE, { waitUntil: 'networkidle0' })
await seed(page)

const look = async (a) => {
  await page.goto(BASE, { waitUntil: 'networkidle0' })
  await page.evaluate((a) => localStorage.setItem('tkf-appearance', JSON.stringify(a)), a)
}
const shot = async (hash, name, full = false) => {
  await page.goto(BASE + hash, { waitUntil: 'networkidle0' })
  await page.reload({ waitUntil: 'networkidle0' })
  await new Promise((r) => setTimeout(r, 2800))
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: full })
}

for (const theme of ['light', 'dark']) {
  await look({ theme, goo: 'home', gooSpeed: 1, gooSize: 1, gooBars: true })
  await shot('#/', `${theme}-home`)
  await shot('#/settings', `${theme}-settings`, true)
  await shot('#/card', `${theme}-card`)
  await look({ theme, goo: 'all', gooSpeed: 1, gooSize: 1, gooBars: true })
  await shot('#/', `${theme}-all`)
}

// 跟随系统：模拟系统切换
await look({ theme: 'system', goo: 'home', gooSpeed: 1, gooSize: 1, gooBars: true })
await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
await page.reload({ waitUntil: 'networkidle0' })
const before = await page.evaluate(() => document.documentElement.dataset.theme)
await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }])
await new Promise((r) => setTimeout(r, 300))
const after = await page.evaluate(() => document.documentElement.dataset.theme)
console.log('system follow:', before, '->', after)

// 空状态：清库看徽章融球
await look({ theme: 'light', goo: 'empty', gooSpeed: 1, gooSize: 1, gooBars: true })
await page.evaluate(async () => {
  const open = indexedDB.open('ai-quota-keeper')
  const db = await new Promise((r) => (open.onsuccess = () => r(open.result)))
  const backup = {}
  for (const s of ['accounts', 'expiries']) {
    backup[s] = await new Promise((r) => (db.transaction(s).objectStore(s).getAll().onsuccess = (e) => r(e.target.result)))
  }
  sessionStorage.setItem('bk', JSON.stringify(backup))
  const tx = db.transaction(['accounts', 'expiries'], 'readwrite')
  tx.objectStore('accounts').clear()
  tx.objectStore('expiries').clear()
  await new Promise((r) => (tx.oncomplete = r))
})
await shot('#/', 'light-empty')
// 还原示例数据
await page.evaluate(async () => {
  const bk = JSON.parse(sessionStorage.getItem('bk'))
  const open = indexedDB.open('ai-quota-keeper')
  const db = await new Promise((r) => (open.onsuccess = () => r(open.result)))
  const tx = db.transaction(['accounts', 'expiries'], 'readwrite')
  for (const s of ['accounts', 'expiries']) for (const row of bk[s]) tx.objectStore(s).put(row)
  await new Promise((r) => (tx.oncomplete = r))
})

console.log('errors:', errors.length ? errors : 'none')
await browser.close()

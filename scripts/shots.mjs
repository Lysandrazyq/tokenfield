// 开发自检：用本机 Chrome 打开开发服务器，写入示例数据，逐页截图并检查报错
// 用法：先 npm run dev，再 node scripts/shots.mjs
import puppeteer from 'puppeteer-core'
import { mkdirSync } from 'node:fs'

const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe'
const BASE = '' + (process.env.BASE || 'http://localhost:2839/') + ''
const OUT = 'shots'
mkdirSync(OUT, { recursive: true })

const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
const errors = []
page.on('pageerror', (e) => errors.push(String(e)))
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))

await page.goto(BASE, { waitUntil: 'networkidle0' })
// 等 Dexie 建好库再写数据
await page.waitForSelector('h1')
await new Promise((r) => setTimeout(r, 500))
await page.evaluate(async () => {
  const open = indexedDB.open('ai-quota-keeper')
  const db = await new Promise((r, j) => ((open.onsuccess = () => r(open.result)), (open.onerror = j)))
  const tx = db.transaction(['accounts', 'expiries', 'settings'], 'readwrite')
  for (const s of ['accounts', 'expiries']) tx.objectStore(s).clear()
  const now = Date.now(), h = 3600e3, iso = (t) => new Date(t).toISOString()
  const acc = tx.objectStore('accounts')
  const base = { note: '', createdAt: iso(now), notifyReset: false, resetKind: 'none' }
  acc.add({ ...base, id: 1, name: 'ChatGPT Pro', provider: 'chatgpt', billing: 'subscription', monthlyCost: 20, currency: 'USD', renewAt: iso(now + 30 * h), resetKind: 'hours', resetHours: 5, resetAnchor: iso(now - 3.2 * h), notifyReset: true, models: 'GPT6.1-sol' })
  acc.add({ ...base, id: 2, name: 'XX 中转站', provider: 'relay', billing: 'balance', monthlyCost: 100, currency: 'CNY', balance: 37.5, models: 'Opus 5.5' })
  acc.add({ ...base, id: 3, name: 'DeepSeek', provider: 'deepseek', billing: 'payg', monthlyCost: 12, currency: 'CNY', models: 'DeepSeek 4.1' })
  const ex = tx.objectStore('expiries')
  ex.add({ id: 1, title: '完全重置券', accountId: 2, expiresAt: iso(now + 20 * 24 * h), done: false })
  ex.add({ id: 2, title: '免费试用到期', accountId: 3, expiresAt: iso(now + 9 * h), done: false })
  tx.objectStore('settings').put({ id: 'main', usdRate: 7.1, remindHours: 24, handle: 'Lysandra_zyq' })
  await new Promise((r) => (tx.oncomplete = r))
})

const shot = async (hash, name, { full = true } = {}) => {
  await page.goto(BASE + hash, { waitUntil: 'networkidle0' })
  await page.reload({ waitUntil: 'networkidle0' })
  await new Promise((r) => setTimeout(r, 2600))
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: full })
}

await shot('#/', 'home')
await shot('#/card', 'card')
await shot('#/account/1', 'edit')
await shot('#/expiry/new', 'expiry')
await shot('#/settings', 'settings')

// 真实点击保存：新建一个 Claude 账号
await page.goto(BASE + '#/account/new', { waitUntil: 'networkidle0' })
await new Promise((r) => setTimeout(r, 1500))
await page.click('.no-scrollbar button:nth-child(2)')
const submit = await page.$('button[type=submit]')
await submit.scrollIntoView()
await submit.click()
await new Promise((r) => setTimeout(r, 800))
const after = await page.evaluate(() => location.hash)
console.log('after save hash:', after)

// 导出分享卡图片
await page.goto(BASE + '#/card', { waitUntil: 'networkidle0' })
await new Promise((r) => setTimeout(r, 2500))
const png = await page.evaluate(async () => {
  const m = await import('/node_modules/.vite/deps/html-to-image.js')
  return m.toPng(document.querySelector('.aspect-\\[3\\/4\\]'), { pixelRatio: 3 })
})
const { writeFileSync } = await import('node:fs')
writeFileSync(`${OUT}/card-export.png`, Buffer.from(png.split(',')[1], 'base64'))

console.log('errors:', errors.length ? errors : 'none')
await browser.close()

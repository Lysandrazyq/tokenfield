// 临时：截参考网站的页面，用于学习视觉风格（不进产品）
import puppeteer from 'puppeteer-core'
import { mkdirSync, writeFileSync } from 'node:fs'

const OUT = 'shots/ref'
mkdirSync(OUT, { recursive: true })
const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const page = await browser.newPage()
await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36')
await page.setViewport({ width: 1440, height: 900 })

const pages = process.argv.slice(2).length
  ? process.argv.slice(2).map((s) => s.split('='))
  : [
      ['home', 'https://www.ignoredone.space/'],
      ['ak-design', 'https://www.ignoredone.space/index.php/arknights_design/'],
      ['ak-graphic', 'https://www.ignoredone.space/index.php/graphic-design-arknights/'],
      ['designweb', 'https://www.ignoredone.space/index.php/designwebsite/'],
    ]
for (const [name, url] of pages) {
  try {
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 90000 })
    for (const t of [1500, 4000]) {
      await new Promise((r) => setTimeout(r, t))
      await page.screenshot({ path: `${OUT}/${name}-${t}.png` })
    }
    // 往下滚，触发懒加载 / 滚动动画
    const h = await page.evaluate(() => document.body.scrollHeight)
    for (let y = 900, k = 0; y < Math.min(h, 9000); y += 900, k++) {
      await page.evaluate((y) => window.scrollTo(0, y), y)
      await new Promise((r) => setTimeout(r, 1200))
      await page.screenshot({ path: `${OUT}/${name}-s${k}.png` })
    }
    const info = await page.evaluate(() => {
      const fonts = new Set()
      document.querySelectorAll('body *').forEach((el) => fonts.add(getComputedStyle(el).fontFamily))
      return {
        title: document.title,
        height: document.body.scrollHeight,
        fonts: [...fonts].slice(0, 15),
        text: document.body.innerText.slice(0, 3000),
        imgs: [...document.images].map((i) => i.currentSrc).filter(Boolean).slice(0, 60),
      }
    })
    writeFileSync(`${OUT}/${name}.json`, JSON.stringify(info, null, 2))
    console.log(name, 'ok', info.height, info.title)
  } catch (e) {
    console.log(name, 'FAIL', String(e).slice(0, 200))
  }
}
await browser.close()

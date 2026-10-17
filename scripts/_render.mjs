// 用真实浏览器渲染官网价格页，拿到用户实际看到的文字（价格多是客户端渲染的）
import puppeteer from 'puppeteer-core'
import { writeFileSync } from 'node:fs'
const pages = JSON.parse(process.argv[2])
const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true })
await Promise.all(Object.entries(pages).map(async ([name, url]) => {
  const p = await browser.newPage()
  await p.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36')
  await p.setExtraHTTPHeaders({ 'Accept-Language': process.argv[3] || 'en-US,en;q=0.9' })
  await p.setViewport({ width: 1400, height: 1000 })
  try {
    await p.goto(url, { waitUntil: 'networkidle2', timeout: 60000 })
    await new Promise((r) => setTimeout(r, 3000))
    // 展开折叠的表格/标签页
    const text = await p.evaluate(() => document.body.innerText)
    writeFileSync(`E:/tmp/px/r-${name}.txt`, 'URL: ' + p.url() + '\n' + text)
    console.log(name, text.length, p.url())
  } catch (e) { console.log(name, 'FAIL', e.message) }
}))
await browser.close()

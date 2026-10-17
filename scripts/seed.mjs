// 开发自检共用：往页面的 IndexedDB 写入示例数据。
// 每次 puppeteer.launch 都是全新的临时浏览器配置，所以每个截图脚本都要自己写一遍。
export async function seed(page) {
  await page.waitForSelector('h1')
  await new Promise((r) => setTimeout(r, 500))
  await page.evaluate(async () => {
    const open = indexedDB.open('ai-quota-keeper')
    const db = await new Promise((r, j) => ((open.onsuccess = () => r(open.result)), (open.onerror = j)))
    const tx = db.transaction(['accounts', 'expiries', 'settings', 'usage'], 'readwrite')
    for (const s of ['accounts', 'expiries']) tx.objectStore(s).clear()
    const now = Date.now(), h = 3600e3, iso = (t) => new Date(t).toISOString()
    const acc = tx.objectStore('accounts')
    const base = { note: '', createdAt: iso(now), notifyReset: false, resetKind: 'none' }
    acc.add({ ...base, id: 1, name: 'Claude Pro', provider: 'claude', billing: 'subscription', planId: 'claude-pro', modelId: 'claude-sonnet-5.5', monthlyCost: 20, currency: 'USD', renewAt: iso(now + 12 * 24 * h), resetKind: 'hours', resetHours: 5, resetAnchor: iso(now - 3.2 * h), notifyReset: true, models: 'Opus 5.5' })
    acc.add({ ...base, id: 2, name: 'XX 中转站', provider: 'relay', billing: 'balance', monthlyCost: 100, currency: 'CNY', balance: 37.5, models: 'Opus 5.5' })
    acc.add({ ...base, id: 3, name: 'DeepSeek', provider: 'deepseek', billing: 'payg', modelId: 'deepseek-flash', monthlyCost: 12, currency: 'CNY', models: 'V4.1 Flash' })
    const ex = tx.objectStore('expiries')
    ex.add({ id: 1, title: '完全重置券', accountId: 2, expiresAt: iso(now + 20 * 24 * h), done: false })
    ex.add({ id: 2, title: '免费试用到期', accountId: 3, expiresAt: iso(now + 9 * h), done: false })
    // 一条已过期的，顺便看警示条纹在浅色下的样子
    ex.add({ id: 3, title: '旧中转站余额', accountId: 2, expiresAt: iso(now - 5 * h), done: false })
    // 使用记录：最近两周每天几次
    const tx2u = tx.objectStore('usage')
    tx2u.clear()
    for (let d = 0; d < 14; d++) {
      const day = new Date(now - d * 24 * h).toISOString().slice(0, 10)
      tx2u.add({ accountId: 1, day, count: 6 + (d % 4), intensity: 'chat' })
      if (d % 2 === 0) tx2u.add({ accountId: 1, day, count: 2, intensity: 'code', hitLimit: d === 2 })
    }
    tx.objectStore('settings').put({ id: 'main', usdRate: 7.1, remindHours: 24, handle: 'Lysandra_zyq' })
    await new Promise((r) => (tx.oncomplete = r))
  })
}

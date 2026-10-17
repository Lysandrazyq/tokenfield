import { useEffect, useRef, useState } from 'react'
import { useStore } from '../lib/store'
import { db, exportData, importData, type Settings as S } from '../db'
import { ensurePermission, isNative, permissionGranted } from '../lib/notify'
import { setAppearance, useAppearance, type ThemeMode } from '../lib/appearance'
import { Segmented, SectionTitle, Toggle } from '../components/ui'

/** 分组列表里的一行：左标签，右输入 */
function InputRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="row">
      <span className="flex-1 text-[15px]">{label}</span>
      {children}
    </label>
  )
}

const inlineInput = 'w-24 bg-transparent text-right text-[15px] tabular-nums text-label-2 outline-none focus:text-label'

export default function Settings() {
  const { settings: stored } = useStore()
  const [s, setS] = useState<S>(stored)
  const [granted, setGranted] = useState(false)
  const [msg, setMsg] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)
  const look = useAppearance()

  useEffect(() => {
    permissionGranted().then(setGranted)
  }, [])

  const update = (patch: Partial<S>) => {
    const next = { ...s, ...patch }
    setS(next)
    db.settings.put(next)
  }

  const flash = (text: string) => {
    setMsg(text)
    setTimeout(() => setMsg(''), 2600)
  }

  const backup = async () => {
    const json = JSON.stringify(await exportData(), null, 2)
    const name = `tokenfield-backup-${new Date().toISOString().slice(0, 10)}.json`
    if (isNative) {
      const { Filesystem, Directory, Encoding } = await import('@capacitor/filesystem')
      const { Share } = await import('@capacitor/share')
      const saved = await Filesystem.writeFile({ path: name, data: json, directory: Directory.Cache, encoding: Encoding.UTF8 })
      await Share.share({ title: '额度终端备份', files: [saved.uri] })
      return
    }
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([json], { type: 'application/json' }))
    a.download = name
    a.click()
    URL.revokeObjectURL(a.href)
  }

  const restore = async (file: File) => {
    try {
      const data = JSON.parse(await file.text())
      if (!confirm('导入会覆盖当前所有数据，确定吗？')) return
      await importData(data)
      // 导入后用新数据刷新输入框
      const fresh = await db.settings.get('main')
      if (fresh) setS({ ...s, ...fresh })
      flash('导入成功')
    } catch (err) {
      flash('导入失败：' + (err as Error).message)
    }
  }

  return (
    <div className="mx-auto max-w-xl space-y-6 pt-4 lg:pt-8">
      <h1 className="rise display px-1 text-[34px]" style={{ '--i': 0 } as React.CSSProperties}>
        设置
      </h1>

      <section className="rise" style={{ '--i': 1 } as React.CSSProperties}>
        <SectionTitle title="外观" />
        <div className="card space-y-1 p-3!">
          <Segmented<ThemeMode>
            value={look.theme}
            onChange={(theme) => setAppearance({ theme })}
            options={[
              { value: 'system', label: '跟随系统' },
              { value: 'light', label: '浅色' },
              { value: 'dark', label: '深色' },
            ]}
          />
          <div className="-mx-3 -mb-3">
            <Toggle
              label="液态玻璃折射"
              hint="导航栏边缘的折射效果；手机发热可以关掉"
              checked={look.refraction}
              onChange={(refraction) => setAppearance({ refraction })}
            />
          </div>
        </div>
      </section>

      <section className="rise" style={{ '--i': 2 } as React.CSSProperties}>
        <SectionTitle title="提醒" />
        <div className="group">
          <div className="row">
            <span className="min-w-0 flex-1">
              <span className="block text-[15px]">通知</span>
              <span className="block text-[12px] text-label-2">{isNative ? 'App 关掉后也会按时提醒' : '网页版只能在页面开着时提醒，装 App 可以后台提醒'}</span>
            </span>
            {granted ? (
              <span className="text-[15px] text-good">已开启</span>
            ) : (
              <button type="button" className="btn-primary px-4! py-1.5! text-[14px]" onClick={async () => setGranted(await ensurePermission())}>
                开启
              </button>
            )}
          </div>
          <InputRow label="续费 / 到期提前提醒">
            <span className="flex items-center gap-1 text-label-2">
              <input
                className={inlineInput}
                type="number"
                min="0"
                inputMode="numeric"
                value={s.remindHours}
                onChange={(e) => update({ remindHours: Math.max(0, Number(e.target.value) || 0) })}
              />
              小时
            </span>
          </InputRow>
        </div>
      </section>

      <section className="rise" style={{ '--i': 3 } as React.CSSProperties}>
        <SectionTitle title="计算" />
        <div className="group">
          <InputRow label="美元汇率">
            <span className="flex items-center gap-1 text-label-2">
              1 美元 =
              <input
                className={`${inlineInput} w-16!`}
                type="number"
                step="0.01"
                min="0"
                inputMode="decimal"
                value={s.usdRate}
                onChange={(e) => update({ usdRate: Number(e.target.value) || 0 })}
              />
              元
            </span>
          </InputRow>
          <InputRow label="月报署名">
            <input className={`${inlineInput} w-40!`} value={s.handle} onChange={(e) => update({ handle: e.target.value })} placeholder="选填" />
          </InputRow>
        </div>
      </section>

      <section className="rise" style={{ '--i': 4 } as React.CSSProperties}>
        <SectionTitle title="数据" />
        <div className="group">
          <button type="button" className="row press w-full text-left text-[15px] text-accent" onClick={backup}>
            导出备份
          </button>
          <button type="button" className="row press w-full text-left text-[15px] text-accent" onClick={() => fileRef.current?.click()}>
            导入备份
          </button>
        </div>
        <p className="mt-2 px-4 text-[12px] text-label-3">所有数据只存在这台设备上，换手机或清缓存前记得导出。</p>
        <input
          ref={fileRef}
          type="file"
          accept="application/json,.json"
          hidden
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) restore(f)
            e.target.value = ''
          }}
        />
      </section>

      <p className="pb-4 text-center text-[12px] text-label-3">Tokenfield 额度终端 · v0.3 · 本地优先，不收集任何数据</p>

      <section className="rise pb-8" style={{ '--i': 5 } as React.CSSProperties}>
        <SectionTitle title="免责声明" />
        <div className="card space-y-3 text-[12px] leading-relaxed text-label-2">
          <p>
            <strong className="text-label">数据准确性：</strong>
            本应用展示的 AI 服务价格和套餐信息来自各服务商官网，核对日期见比价页每条来源链接。价格可能随时变更，以各服务商官网最新公示为准。本应用不对价格信息的实时性、准确性承担任何责任。
          </p>
          <p>
            <strong className="text-label">品牌图标：</strong>
            本应用展示的 ChatGPT、Claude、Gemini、DeepSeek、Kimi、智谱 GLM、通义千问、豆包、MiniMax 等服务商图标均为其各自公司的商标，仅用于帮助用户识别已录入的订阅服务，不代表本应用与上述公司存在任何合作或从属关系。
          </p>
          <p>
            <strong className="text-label">数据隐私：</strong>
            本应用所有数据（包括账单金额、到期时间等）仅存储在您本人的设备本地，不上传、不共享、不收集。本应用无服务器、无账号系统，开发者无法访问您的任何数据。
          </p>
          <p>
            <strong className="text-label">非官方应用：</strong>
            本应用是独立开发者作品，与以上任何 AI 服务商无关。使用本应用不影响您与各服务商之间的任何协议。
          </p>
          <p className="text-label-3">
            如发现价格信息有误，欢迎在 X 上联系 @Lysandra_zyq 反馈。
          </p>
        </div>
      </section>

      {msg && (
        <div className="liquid fixed inset-x-0 bottom-28 z-50 mx-auto w-fit rounded-full px-5 py-2.5 text-[14px]" role="status">
          {msg}
        </div>
      )}
    </div>
  )
}

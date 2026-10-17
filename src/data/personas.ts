import type { Intensity } from '../db'

/**
 * 用法画像：帮用户快速定位「我大概是哪种人」，再在比价页微调次数。
 * 次数是按这类用法的典型节奏给的起点，不是统计数据，界面上允许拖动修改。
 */
export interface Persona {
  key: string
  name: string
  who: string
  intensity: Intensity
  usesPerMonth: number
  advice: string
}

export const PERSONAS: Persona[] = [
  {
    key: 'casual',
    name: '偶尔问问',
    who: '学生、上班族，查资料、翻译、问问题',
    intensity: 'chat',
    usesPerMonth: 150,
    advice: '用量小的话，按量付费或免费版通常就够了。国内模型价格低，一个月几块钱甚至几毛钱。',
  },
  {
    key: 'daily',
    name: '每天都用',
    who: '天天聊、写东西，离不开它',
    intensity: 'chat',
    usesPerMonth: 900,
    advice: '天天用、还想用最强的海外模型，会员更省心；只用国内模型的话按量付费依然很便宜。',
  },
  {
    key: 'writer',
    name: '写作 / 读文档',
    who: '运营、研究、写论文，常贴长文',
    intensity: 'write',
    usesPerMonth: 400,
    advice: '长文本输入很费 token。经常贴长文、又要用海外旗舰模型的话，会员一般更划算。',
  },
  {
    key: 'coder',
    name: '写代码',
    who: '开发者，在聊天窗口里改代码',
    intensity: 'code',
    usesPerMonth: 600,
    advice: '对话式写代码用量中等。挑一个便宜的强模型按量用通常更省；每天高强度用就选会员。',
  },
  {
    key: 'agent',
    name: '编程 Agent',
    who: '用 Claude Code、Codex、Cursor 自动写代码',
    intensity: 'agent',
    usesPerMonth: 180,
    advice: 'Agent 一个任务就要几十万 token，按量付费很容易超过会员价。重度使用基本都是会员更划算。',
  },
  {
    key: 'team',
    name: '项目里调用 API',
    who: '自己做产品，程序里批量调用',
    intensity: 'write',
    usesPerMonth: 3000,
    advice: '程序调用只能走 API，会员不能用在你自己的产品里。重点比较按量价格和缓存命中价。',
  },
]

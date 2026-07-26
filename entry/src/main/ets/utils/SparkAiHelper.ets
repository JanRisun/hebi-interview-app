// SparkAiHelper.ets — 讯飞星火大模型（Spark）答题点评
// 通过 WebSocket 调用星火 chat 接口，用纯 ArkTS HMAC-SHA256 生成鉴权签名（不依赖 cryptoFramework）。
// 输入「题目 + 语音转写文本」，输出结构化点评：总分 / 等级 / 维度分 / 点评多段 / 标签 / 润色前后。
//
// 接入步骤：
//   1. 到 https://console.xfyun.cn → 应用 → 添加「星火认知大模型」服务
//   2. 在应用「服务接口认证信息」中获取 APIKey / APISecret（与语音识别的密钥不同）
//   3. 将下方 XF_SPARK_API_KEY / XF_SPARK_API_SECRET 替换为你的真实值
import { webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CloudAsrHelper } from './CloudAsrHelper';
import {
  PROT_APP_ID as XF_APP_ID,
  PROT_SPARK_API_KEY as XF_SPARK_API_KEY,
  PROT_SPARK_API_SECRET as XF_SPARK_API_SECRET
} from './Protected';

const DOMAIN: number = 0x0003;
const TAG: string = 'SparkAiHelper';

// ---------------------- 密钥配置（已迁移至 ./Protected.ets，被 .gitignore 排除） ----------------------
// 星火密钥：PROT_SPARK_API_KEY / PROT_SPARK_API_SECRET（与语音听写不是同一套）

// 星火版本 / domain 映射：v3.5 → generalv3.5（也可按需改成 v4.0 / generalv4）
const SPARK_HOST: string = 'spark-api.xf-yun.com';
const SPARK_PATH: string = '/v3.5/chat';
const SPARK_DOMAIN: string = 'generalv3.5';

// 星火返回的结构化点评结果
export interface AiReviewResult {
  score: number;          // 综合分 0-100
  level: string;          // 等级文字：优秀 / 良好 / 合格 / 待提升
  summary: string;        // 一句话总评
  dimensions: AiDimension[]; // 维度评分（ratio 0.0-1.0）
  review: string[];       // 点评段落
  tags: string[];         // 标签
  polishBefore: string;   // 润色前（取自转写稿的一句口语化原话）
  polishAfter: string;    // 润色后（对应书面化表达）
}

export interface AiDimension {
  label: string;
  ratio: number;
}

// 默认维度（当模型未返回时兜底）
const DEFAULT_DIMENSIONS: AiDimension[] = [
  { label: '内容完整度', ratio: 0.8 },
  { label: '逻辑条理', ratio: 0.8 },
  { label: '语言表达', ratio: 0.8 },
  { label: '亮点 / 创新', ratio: 0.75 }
];

// 星火 WebSocket 请求结构（ArkTS 严格模式需显式接口）
interface SparkHeader {
  app_id: string;
  uid: string;
}
interface SparkRequest {
  header: SparkHeader;
  parameter: SparkParameter;
  payload: SparkPayload;
}
interface SparkParameter {
  chat: SparkChat;
}
interface SparkChat {
  domain: string;
  temperature: number;
  max_tokens: number;
  auditing: string;
}
interface SparkPayload {
  message: SparkMessage;
}
interface SparkMessage {
  text: SparkTextItem[];
}
interface SparkTextItem {
  role: string;
  content: string;
}

export class SparkAiHelper {
  // 生成带鉴权参数的星火 WebSocket 地址
  private static buildAuthUrl(): string {
    const date: string = new Date().toUTCString();
    const signatureOrigin: string =
      'host: ' + SPARK_HOST + '\n' +
      'date: ' + date + '\n' +
      'GET ' + SPARK_PATH + ' HTTP/1.1';

    const shaBytes: Uint8Array = CloudAsrHelper.hmacSha256(XF_SPARK_API_SECRET, signatureOrigin);
    const base64: util.Base64Helper = new util.Base64Helper();
    const signature: string = base64.encodeToStringSync(shaBytes);

    const authorizationOrigin: string =
      'api_key="' + XF_SPARK_API_KEY + '", algorithm="hmac-sha256", ' +
      'headers="host date request-line", signature="' + signature + '"';
    const authorization: string = base64.encodeToStringSync(
      new util.TextEncoder().encode(authorizationOrigin)
    );

    return 'wss://' + SPARK_HOST + SPARK_PATH +
      '?authorization=' + encodeURIComponent(authorization) +
      '&date=' + encodeURIComponent(date) +
      '&host=' + SPARK_HOST;
  }

  // 生成提示词：要求模型严格返回 JSON
  private static buildPrompt(questionTitle: string, questionPrompt: string, transcript: string): string {
    const userText: string = transcript && transcript.length > 0
      ? transcript
      : '（用户未提供语音转写稿，请基于题目仅给出通用答题思路点评）';
    return '你是一位资深面试官与表达教练。请基于下面的「面试题目」与「考生语音转写稿」进行专业点评。\n' +
      '面试题目：' + questionTitle + '\n' +
      '题目提示：' + (questionPrompt || '（无）') + '\n' +
      '考生转写稿：' + userText + '\n\n' +
      '请严格按照以下 JSON 格式输出（不要输出任何多余文字、不要使用 markdown 代码块）：\n' +
      '{\n' +
      '  "score": 0到100的整数（综合评分）,\n' +
      '  "level": "优秀/良好/合格/待提升 之一",\n' +
      '  "summary": "一句话总评（不超过30字）",\n' +
      '  "dimensions": [\n' +
      '    {"label":"内容完整度","ratio":0.0到1.0的小数},\n' +
      '    {"label":"逻辑条理","ratio":0.0到1.0的小数},\n' +
      '    {"label":"语言表达","ratio":0.0到1.0的小数},\n' +
      '    {"label":"亮点/创新","ratio":0.0到1.0的小数}\n' +
      '  ],\n' +
      '  "review": ["点评段落1","点评段落2", ...],\n' +
      '  "tags": ["标签1","标签2", ...],\n' +
      '  "polishBefore": "从转写稿中提取的一句典型口语化原话",\n' +
      '  "polishAfter": "该句对应的书面化、精炼的润色版本"\n' +
      '}';
  }

  // 调用星火，返回结构化点评结果
  static reviewAnswer(questionTitle: string, questionPrompt: string, transcript: string): Promise<AiReviewResult> {
    if (XF_SPARK_API_KEY.startsWith('YOUR_') || XF_SPARK_API_SECRET.startsWith('YOUR_')) {
      return Promise.reject(new Error('星火密钥未配置：请在 SparkAiHelper.ets 填入 XF_SPARK_API_KEY 与 XF_SPARK_API_SECRET'));
    }

    const prompt: string = SparkAiHelper.buildPrompt(questionTitle, questionPrompt, transcript);
    const url: string = SparkAiHelper.buildAuthUrl();

    return new Promise<AiReviewResult>((resolve, reject): void => {
      const ws = webSocket.createWebSocket();
      let content: string = '';
      let settled: boolean = false;

      const safeResolve = (r: AiReviewResult): void => {
        if (settled) return;
        settled = true;
        try { ws.close(); } catch (e) { /* ignore */ }
        resolve(r);
      };
      const safeReject = (e: Error): void => {
        if (settled) return;
        settled = true;
        try { ws.close(); } catch (e2) { /* ignore */ }
        reject(e);
      };

      ws.on('open', (err: BusinessError, _value: Object): void => {
        if (err) {
          safeReject(new Error('星火连接打开失败: ' + err.message));
          return;
        }
        const req: SparkRequest = {
          header: { app_id: XF_APP_ID, uid: 'hebi_user' } as SparkHeader,
          parameter: {
            chat: {
              domain: SPARK_DOMAIN,
              temperature: 0.7,
              max_tokens: 2048,
              auditing: 'default'
            }
          },
          payload: {
            message: {
              text: [
                { role: 'system', content: '你是专业的面试官点评助手，输出严格 JSON。' },
                { role: 'user', content: prompt }
              ]
            }
          }
        };
        try {
          ws.send(JSON.stringify(req));
        } catch (e) {
          safeReject(new Error('星火请求发送失败: ' + ((e as BusinessError)?.message ?? String(e))));
        }
      });

      ws.on('message', (err: BusinessError, value: string | ArrayBuffer): void => {
        if (err) {
          safeReject(new Error('星火消息接收失败: ' + err.message));
          return;
        }
        const text: string = typeof value === 'string' ? value : '';
        if (!text) return;
        let json: object;
        try {
          json = JSON.parse(text) as object;
        } catch (e) {
          return; // 非 JSON（如心跳），忽略
        }
        const header = (json as Record<string, Object>)['header'] as Record<string, Object> | undefined;
        if (header && typeof header['code'] === 'number' && (header['code'] as number) !== 0) {
          safeReject(new Error('星火返回错误码 ' + header['code'] + ': ' + (header['message'] as string)));
          return;
        }
        const payload = (json as Record<string, Object>)['payload'] as Record<string, Object> | undefined;
        if (!payload) return;
        const choices = payload['choices'] as Record<string, Object> | undefined;
        if (!choices) return;
        const texts = choices['text'] as Array<Record<string, Object>> | undefined;
        if (texts && texts.length > 0) {
          const c: string = (texts[0]['content'] as string) ?? '';
          content += c;
        }
        const status: number = (header && typeof header['status'] === 'number') ? (header['status'] as number) : 0;
        if (status === 2) {
          try {
            safeResolve(SparkAiHelper.parseResult(content));
          } catch (e) {
            safeReject(new Error('星火结果解析失败: ' + ((e as Error)?.message ?? String(e))));
          }
        }
      });

      ws.on('error', (err: BusinessError): void => {
        safeReject(new Error('星火连接错误: ' + err.message));
      });

      ws.on('close', (err: BusinessError, _value: Object): void => {
        if (!settled) {
          // 连接关闭但未收到完整结果
          if (content && content.length > 0) {
            try {
              safeResolve(SparkAiHelper.parseResult(content));
            } catch (e) {
              safeReject(new Error('星火连接提前关闭，结果不完整'));
            }
          } else {
            safeReject(new Error('星火连接已关闭（' + (err?.message ?? '未知原因') + '）'));
          }
        }
      });

      ws.connect(url).catch((e: BusinessError): void => {
        safeReject(new Error('星火建立连接失败: ' + (e?.message ?? String(e))));
      });
    });
  }

  // 解析模型返回的 JSON（容错：去掉代码块标记）
  private static parseResult(raw: string): AiReviewResult {
    let s: string = (raw || '').trim();
    const fence = s.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fence) {
      s = fence[1].trim();
    }
    const obj = JSON.parse(s) as Record<string, Object>;

    const score: number = typeof obj['score'] === 'number' ? (obj['score'] as number) : 0;
    const level: string = typeof obj['level'] === 'string' ? (obj['level'] as string) : '待提升';
    const summary: string = typeof obj['summary'] === 'string' ? (obj['summary'] as string) : '';

    let dimensions: AiDimension[] = DEFAULT_DIMENSIONS;
    if (Array.isArray(obj['dimensions'])) {
      const dims = obj['dimensions'] as Array<Record<string, Object>>;
      const parsed: AiDimension[] = [];
      for (const d of dims) {
        const label: string = typeof d['label'] === 'string' ? (d['label'] as string) : '维度';
        const ratio: number = typeof d['ratio'] === 'number' ? (d['ratio'] as number) : 0.8;
        parsed.push({ label, ratio: Math.max(0, Math.min(1, ratio)) });
      }
      if (parsed.length > 0) {
        dimensions = parsed;
      }
    }

    let review: string[] = [];
    if (Array.isArray(obj['review'])) {
      review = (obj['review'] as Array<Object>).map((x: Object): string => String(x)).filter((x: string): boolean => x.length > 0);
    }

    let tags: string[] = [];
    if (Array.isArray(obj['tags'])) {
      tags = (obj['tags'] as Array<Object>).map((x: Object): string => String(x)).filter((x: string): boolean => x.length > 0);
    }

    const polishBefore: string = typeof obj['polishBefore'] === 'string' ? (obj['polishBefore'] as string) : '';
    const polishAfter: string = typeof obj['polishAfter'] === 'string' ? (obj['polishAfter'] as string) : '';

    return { score, level, summary, dimensions, review, tags, polishBefore, polishAfter };
  }
}

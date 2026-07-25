// CloudAsrHelper.ets — 讯飞录音文件转写 v2 HTTP 实现（替代 WebSocket IAT，避免本机 WebSocket/Crypto 兼容问题）
// 接入步骤：
//   1. 到 https://console.xfyun.cn → 应用 → 添加「录音文件转写」服务
//   2. 服务页面查看 secretKey（可能与 IAT 的 APISecret 不同，用转写服务的 secretKey）
//   3. 每日免费 500 次，商用前申请正式授权
// ⚠️ 若 secretKey 与 IAT 不同，需改动下方 XF_IFASR_SECRET
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';

const DOMAIN: number = 0x0002;
const TAG: string = 'CloudAsrHelper';

// ---------------------- 密钥配置 ----------------------
const XF_APP_ID: string = 'a865969a';
const XF_IFASR_SECRET: string = '13c70b35ba17d9d59cc8f63f921ef75a'; // 录音文件转写服务的 secretKey（可能与 IAT APISecret 共用，若不同请替换）

// 轮询参数
const POLL_INTERVAL_MS: number = 5000;  // 每 5 秒查一次
const POLL_MAX: number = 120;            // 最多等 10 分钟

// 录音文件转写 v2 响应结构（用于约束 JSON 字面值，规避 arkts-no-untyped-obj-literals）
interface IfasrUploadContent {
  orderId: string;
  taskEstimateTime: number;
}
interface IfasrUploadResp {
  code: string;
  descInfo: string;
  content: IfasrUploadContent;
}
interface IfasrResultContent {
  orderResult: string;
}
interface IfasrResultResp {
  code: string;
  descInfo: string;
  content: IfasrResultContent;
}
interface IfasrSentence {
  bg: string;
  ed: string;
  onebest: string;
  speaker: string;
}

export class CloudAsrHelper {
  // signa = Base64(HmacSHA1(MD5(appId + ts), secretKey))
  // 纯 ArkTS 实现，不依赖任何 native crypto 模块（本机 cryptoFramework 不可用）
  private static async generateSigna(appId: string, ts: string, secretKey: string): Promise<string> {
    const md5Hex: string = CloudAsrHelper.md5(appId + ts);
    const macBytes: Uint8Array = CloudAsrHelper.hmacSha1(secretKey, md5Hex);
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.encodeToStringSync(macBytes);
  }

  // ---------------------- 纯 JS MD5（RFC 1321） ----------------------
  private static readonly MD5_K: number[] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
  ];
  private static readonly MD5_S: number[] = [
    7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
    5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
    4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
    6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
  ];

  private static md5(input: string): string {
    const msg: Uint8Array = new util.TextEncoder().encodeInto(input);
    const len: number = msg.byteLength;
    const bitLen: number = len * 8;
    const newLen: number = (((len + 8) >> 6) + 1) << 6;
    const buf: Uint8Array = new Uint8Array(newLen);
    buf.set(msg);
    buf[len] = 0x80;
    const off: number = newLen - 8;
    buf[off] = bitLen & 0xff;
    buf[off + 1] = (bitLen >>> 8) & 0xff;
    buf[off + 2] = (bitLen >>> 16) & 0xff;
    buf[off + 3] = (bitLen >>> 24) & 0xff;
    buf[off + 4] = 0;
    buf[off + 5] = 0;
    buf[off + 6] = 0;
    buf[off + 7] = 0;

    let a0: number = 0x67452301;
    let b0: number = 0xefcdab89;
    let c0: number = 0x98badcfe;
    let d0: number = 0x10325476;

    const M: number[] = new Array<number>(16);
    for (let i: number = 0; i < newLen; i += 64) {
      for (let j: number = 0; j < 16; j++) {
        const idx: number = i + j * 4;
        M[j] = (buf[idx] | (buf[idx + 1] << 8) | (buf[idx + 2] << 16) | (buf[idx + 3] << 24)) | 0;
      }
      let A: number = a0;
      let B: number = b0;
      let C: number = c0;
      let D: number = d0;
      for (let k: number = 0; k < 64; k++) {
        let F: number = 0;
        let g: number = 0;
        if (k < 16) {
          F = (B & C) | (~B & D);
          g = k;
        } else if (k < 32) {
          F = (D & B) | (~D & C);
          g = (5 * k + 1) % 16;
        } else if (k < 48) {
          F = B ^ C ^ D;
          g = (3 * k + 5) % 16;
        } else {
          F = C ^ (B | ~D);
          g = (7 * k) % 16;
        }
        F = (F + A + CloudAsrHelper.MD5_K[k] + M[g]) | 0;
        const tmp: number = D;
        D = C;
        C = B;
        B = (B + CloudAsrHelper.rotl(F, CloudAsrHelper.MD5_S[k])) | 0;
        A = tmp;
      }
      a0 = (a0 + A) | 0;
      b0 = (b0 + B) | 0;
      c0 = (c0 + C) | 0;
      d0 = (d0 + D) | 0;
    }
    return CloudAsrHelper.toHexLE(a0) + CloudAsrHelper.toHexLE(b0) +
      CloudAsrHelper.toHexLE(c0) + CloudAsrHelper.toHexLE(d0);
  }

  // ---------------------- 纯 JS SHA1（RFC 3174） ----------------------
  private static sha1(msg: Uint8Array): Uint8Array {
    const len: number = msg.byteLength;
    const bitLen: number = len * 8;
    const kpad: number = (56 - ((len + 1) % 64) + 64) % 64;
    const totalLen: number = len + 1 + kpad + 8;
    const buf: Uint8Array = new Uint8Array(totalLen);
    buf.set(msg);
    buf[len] = 0x80;
    const off: number = totalLen - 8;
    buf[off] = (bitLen >>> 24) & 0xff;
    buf[off + 1] = (bitLen >>> 16) & 0xff;
    buf[off + 2] = (bitLen >>> 8) & 0xff;
    buf[off + 3] = bitLen & 0xff;
    buf[off + 4] = 0;
    buf[off + 5] = 0;
    buf[off + 6] = 0;
    buf[off + 7] = 0;

    let h0: number = 0x67452301;
    let h1: number = 0xEFCDAB89;
    let h2: number = 0x98BADCFE;
    let h3: number = 0x10325476;
    let h4: number = 0xC3D2E1F0;

    const w: number[] = new Array<number>(80);
    for (let i: number = 0; i < totalLen; i += 64) {
      for (let j: number = 0; j < 16; j++) {
        const idx: number = i + j * 4;
        w[j] = ((buf[idx] << 24) | (buf[idx + 1] << 16) | (buf[idx + 2] << 8) | buf[idx + 3]) | 0;
      }
      for (let j: number = 16; j < 80; j++) {
        w[j] = CloudAsrHelper.rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
      }
      let a: number = h0;
      let b: number = h1;
      let c: number = h2;
      let d: number = h3;
      let e: number = h4;
      for (let j: number = 0; j < 80; j++) {
        let f: number = 0;
        let kk: number = 0;
        if (j < 20) {
          f = (b & c) | (~b & d);
          kk = 0x5A827999;
        } else if (j < 40) {
          f = b ^ c ^ d;
          kk = 0x6ED9EBA1;
        } else if (j < 60) {
          f = (b & c) | (b & d) | (c & d);
          kk = 0x8F1BBCDC;
        } else {
          f = b ^ c ^ d;
          kk = 0xCA62C1D6;
        }
        const temp: number = (CloudAsrHelper.rotl(a, 5) + f + e + kk + w[j]) | 0;
        e = d;
        d = c;
        c = CloudAsrHelper.rotl(b, 30);
        b = a;
        a = temp;
      }
      h0 = (h0 + a) | 0;
      h1 = (h1 + b) | 0;
      h2 = (h2 + c) | 0;
      h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0;
    }
    const out: Uint8Array = new Uint8Array(20);
    CloudAsrHelper.writeBe32(out, 0, h0);
    CloudAsrHelper.writeBe32(out, 4, h1);
    CloudAsrHelper.writeBe32(out, 8, h2);
    CloudAsrHelper.writeBe32(out, 12, h3);
    CloudAsrHelper.writeBe32(out, 16, h4);
    return out;
  }

  // ---------------------- 纯 JS HMAC-SHA1 ----------------------
  private static hmacSha1(key: string, message: string): Uint8Array {
    const blockSize: number = 64;
    let keyBytes: Uint8Array = new util.TextEncoder().encodeInto(key);
    if (keyBytes.byteLength > blockSize) {
      keyBytes = CloudAsrHelper.sha1(keyBytes);
    }
    const paddedKey: Uint8Array = new Uint8Array(blockSize);
    paddedKey.set(keyBytes);
    const ipad: Uint8Array = new Uint8Array(blockSize);
    const opad: Uint8Array = new Uint8Array(blockSize);
    for (let i: number = 0; i < blockSize; i++) {
      ipad[i] = paddedKey[i] ^ 0x36;
      opad[i] = paddedKey[i] ^ 0x5c;
    }
    const msgBytes: Uint8Array = new util.TextEncoder().encodeInto(message);
    const inner: Uint8Array = new Uint8Array(blockSize + msgBytes.byteLength);
    inner.set(ipad);
    inner.set(msgBytes, blockSize);
    const innerHash: Uint8Array = CloudAsrHelper.sha1(inner);
    const outer: Uint8Array = new Uint8Array(blockSize + 20);
    outer.set(opad);
    outer.set(innerHash, blockSize);
    return CloudAsrHelper.sha1(outer);
  }

  private static rotl(n: number, s: number): number {
    return ((n << s) | (n >>> (32 - s))) | 0;
  }

  private static toHexLE(n: number): string {
    let s: string = '';
    for (let i: number = 0; i < 4; i++) {
      const b: number = (n >>> (i * 8)) & 0xff;
      const h: string = b.toString(16);
      s += h.length === 1 ? '0' + h : h;
    }
    return s;
  }

  private static writeBe32(buf: Uint8Array, off: number, n: number): void {
    buf[off] = (n >>> 24) & 0xff;
    buf[off + 1] = (n >>> 16) & 0xff;
    buf[off + 2] = (n >>> 8) & 0xff;
    buf[off + 3] = n & 0xff;
  }

  // 把 WAV 文件通过讯飞录音文件转写 v2 HTTP 转成文字
  static async transcribe(wavPath: string): Promise<string> {
    // 1) 检查密钥
    if (XF_APP_ID.startsWith('YOUR_')) {
      throw new Error('CloudAsrHelper 密钥未配置，请到讯飞控制台添加录音文件转写服务，填入 XF_APP_ID 和 XF_IFASR_SECRET');
    }

    // 2) 读取完整 WAV 文件
    let stat: fileIo.Stat;
    let file: fileIo.File;
    try {
      stat = fileIo.statSync(wavPath);
      file = fileIo.openSync(wavPath, fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      throw new Error('CloudAsrHelper 无法读取录音文件: ' + wavPath);
    }
    const total: number = stat.size;
    const allBuf: ArrayBuffer = new ArrayBuffer(total);
    try {
      fileIo.readSync(file.fd, allBuf);
    } finally {
      fileIo.closeSync(file.fd);
    }
    if (total <= 44) {
      throw new Error('CloudAsrHelper: 录音文件无有效数据');
    }
    const wavBytes: Uint8Array = new Uint8Array(allBuf);
    const pcmSize: number = total - 44;
    // 估算时长（秒）：16k 单声道 16bit → 32000 字节/秒
    const estDuration: number = Math.ceil(pcmSize / 32000);

    // 3) 上传 WAV → 获取 orderId
    const tsUpload: string = Math.floor(Date.now() / 1000).toString();
    const signaUpload: string = await CloudAsrHelper.generateSigna(XF_APP_ID, tsUpload, XF_IFASR_SECRET);
    const uploadParams: string =
      `appId=${XF_APP_ID}&ts=${tsUpload}&signa=${encodeURIComponent(signaUpload)}` +
      `&fileName=answer.wav&fileSize=${total}&duration=${estDuration}&resultType=transfer`;

    const httpReq: http.HttpRequest = http.createHttp();
    let uploadResp: http.HttpResponse;
    try {
      uploadResp = await httpReq.request(
        `https://raasr.xfyun.cn/v2/api/upload?${uploadParams}`,
        {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/octet-stream' },
          extraData: allBuf
        }
      );
    } catch (e) {
      throw new Error('文件上传失败（请检查网络或讯飞密钥）: ' + ((e as BusinessError)?.message ?? String(e)));
    }

    const uploadJson: IfasrUploadResp = JSON.parse(uploadResp.result as string) as IfasrUploadResp;
    if (uploadJson.code !== '000000') {
      throw new Error(`上传失败(${uploadJson.code}): ${uploadJson.descInfo}`);
    }
    const orderId: string = uploadJson.content.orderId;
    hilog.info(DOMAIN, TAG, '转写任务已创建: %{public}s', orderId);

    // 4) 轮询结果
    for (let i: number = 0; i < POLL_MAX; i++) {
      await CloudAsrHelper.delay(POLL_INTERVAL_MS);
      const tsPoll: string = Math.floor(Date.now() / 1000).toString();
      const signaPoll: string = await CloudAsrHelper.generateSigna(XF_APP_ID, tsPoll, XF_IFASR_SECRET);
      const pollParams: string =
        `appId=${XF_APP_ID}&ts=${tsPoll}&signa=${encodeURIComponent(signaPoll)}&orderId=${orderId}&resultType=transfer`;

      let pollResp: http.HttpResponse;
      try {
        pollResp = await httpReq.request(
          `https://raasr.xfyun.cn/v2/api/getResult?${pollParams}`,
          { method: http.RequestMethod.GET }
        );
      } catch (e) {
        // 网络抖动，继续轮询
        continue;
      }
      const pollJson: IfasrResultResp = JSON.parse(pollResp.result as string) as IfasrResultResp;
      if (pollJson.code !== '000000') {
        // 任务仍在处理中（如 26605="处理中"），继续轮询
        hilog.info(DOMAIN, TAG, '轮询 %{public}d: %{public}s', i, pollJson.descInfo ?? '');
        continue;
      }
      // 解析结果 → 拼接 onebest 字段
      try {
        const sentences: IfasrSentence[] = JSON.parse(pollJson.content.orderResult) as IfasrSentence[];
        let text: string = '';
        for (const s of sentences) {
          text += s.onebest;
        }
        httpReq.destroy();
        return text;
      } catch (e) {
        // orderResult 解析失败（可能格式未就绪），稍后重试
        continue;
      }
    }
    httpReq.destroy();
    throw new Error('转写超时（已等待 ' + Math.floor(POLL_MAX * POLL_INTERVAL_MS / 1000) + ' 秒），请稍后重试');
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>(ok => setTimeout(ok, ms));
  }
}

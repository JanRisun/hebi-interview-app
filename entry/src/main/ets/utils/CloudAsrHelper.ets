// CloudAsrHelper.ets — 讯飞语音听写（IAT）WebSocket 实现（替代付费的录音文件转写，走免费额度）
// 纯 ArkTS 实现 HMAC-SHA256 鉴权，避免本机 cryptoFramework 兼容问题
// 接入步骤：
//   1. 到 https://console.xfyun.cn → 应用 a865969a → 添加「语音听写」服务（IAT，通常含免费额度）
//   2. 服务页面查看 APIKey / APISecret，填入下方 XF_IAT_API_KEY / XF_IAT_API_SECRET
//   3. 录音需为 16k 单声道 16bit 的 WAV（与 AudioAnswer 录音参数一致）
import { http, webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import {
  PROT_APP_ID as XF_APP_ID,
  PROT_IAT_API_KEY as XF_IAT_API_KEY,
  PROT_IAT_API_SECRET as XF_IAT_API_SECRET,
  PROT_IFASR_SECRET as XF_IFASR_SECRET
} from './Protected';

const DOMAIN: number = 0x0002;
const TAG: string = 'CloudAsrHelper';

// ---------------------- 密钥配置（已迁移至 ./Protected.ets，被 .gitignore 排除） ----------------------
// 语音听写（IAT）密钥：PROT_IAT_API_KEY / PROT_IAT_API_SECRET
// 录音文件转写（已弃用）：PROT_IFASR_SECRET

// 轮询参数（IAT 已不再使用，保留以防回退）
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

// 语音听写（IAT）WebSocket 请求/响应结构（ArkTS 严格模式需显式接口）
interface IatBusiness {
  language: string;
  domain: string;
  accent: string;
  vad_eos: number;
}
interface IatData {
  status: number;
  format: string;
  encoding: string;
  audio: string;
}
interface IatCommon {
  app_id: string;
}
interface IatFrame {
  common: IatCommon;
  business: IatBusiness;
  data: IatData;
}
interface IatCw {
  w: string;
}
interface IatWs {
  cw: IatCw[];
}
interface IatResult {
  ws: IatWs[];
}
interface IatDataResp {
  status: number;
  result?: IatResult;
}
interface IatResp {
  code: number;
  message?: string;
  data?: IatDataResp;
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
    const msg: Uint8Array = new util.TextEncoder().encode(input);
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
    let keyBytes: Uint8Array = new util.TextEncoder().encode(key);
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
    const msgBytes: Uint8Array = new util.TextEncoder().encode(message);
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

  private static rotr(n: number, s: number): number {
    return ((n >>> s) | (n << (32 - s))) | 0;
  }

  // ---------------------- 纯 JS SHA-256（FIPS 180-4） ----------------------
  private static readonly SHA256_K: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  public static sha256(msg: Uint8Array): Uint8Array {
    const len: number = msg.byteLength;
    const bitLen: number = len * 8;
    const kpad: number = (56 - ((len + 1) % 64) + 64) % 64;
    const totalLen: number = len + 1 + kpad + 8;
    const buf: Uint8Array = new Uint8Array(totalLen);
    buf.set(msg);
    buf[len] = 0x80;
    const hi: number = Math.floor(bitLen / 0x100000000);
    const lo: number = bitLen >>> 0;
    const off: number = totalLen - 8;
    buf[off] = (hi >>> 24) & 0xff;
    buf[off + 1] = (hi >>> 16) & 0xff;
    buf[off + 2] = (hi >>> 8) & 0xff;
    buf[off + 3] = hi & 0xff;
    buf[off + 4] = (lo >>> 24) & 0xff;
    buf[off + 5] = (lo >>> 16) & 0xff;
    buf[off + 6] = (lo >>> 8) & 0xff;
    buf[off + 7] = lo & 0xff;

    let h0: number = 0x6a09e667;
    let h1: number = 0xbb67ae85;
    let h2: number = 0x3c6ef372;
    let h3: number = 0xa54ff53a;
    let h4: number = 0x510e527f;
    let h5: number = 0x9b05688c;
    let h6: number = 0x1f83d9ab;
    let h7: number = 0x5be0cd19;

    const w: number[] = new Array<number>(64);
    for (let i: number = 0; i < totalLen; i += 64) {
      for (let j: number = 0; j < 16; j++) {
        const idx: number = i + j * 4;
        w[j] = ((buf[idx] << 24) | (buf[idx + 1] << 16) | (buf[idx + 2] << 8) | buf[idx + 3]) | 0;
      }
      for (let j: number = 16; j < 64; j++) {
        const s0: number = (CloudAsrHelper.rotr(w[j - 15], 7) ^ CloudAsrHelper.rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3)) | 0;
        const s1: number = (CloudAsrHelper.rotr(w[j - 2], 17) ^ CloudAsrHelper.rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10)) | 0;
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0;
      }
      let a: number = h0;
      let b: number = h1;
      let c: number = h2;
      let d: number = h3;
      let e: number = h4;
      let f: number = h5;
      let g: number = h6;
      let h: number = h7;
      for (let j: number = 0; j < 64; j++) {
        const S1: number = (CloudAsrHelper.rotr(e, 6) ^ CloudAsrHelper.rotr(e, 11) ^ CloudAsrHelper.rotr(e, 25)) | 0;
        const ch: number = (e & f) ^ (~e & g);
        const temp1: number = (h + S1 + ch + CloudAsrHelper.SHA256_K[j] + w[j]) | 0;
        const S0: number = (CloudAsrHelper.rotr(a, 2) ^ CloudAsrHelper.rotr(a, 13) ^ CloudAsrHelper.rotr(a, 22)) | 0;
        const maj: number = (a & b) ^ (a & c) ^ (b & c);
        const temp2: number = (S0 + maj) | 0;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) | 0;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0;
      h1 = (h1 + b) | 0;
      h2 = (h2 + c) | 0;
      h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0;
      h5 = (h5 + f) | 0;
      h6 = (h6 + g) | 0;
      h7 = (h7 + h) | 0;
    }
    const out: Uint8Array = new Uint8Array(32);
    CloudAsrHelper.writeBe32(out, 0, h0);
    CloudAsrHelper.writeBe32(out, 4, h1);
    CloudAsrHelper.writeBe32(out, 8, h2);
    CloudAsrHelper.writeBe32(out, 12, h3);
    CloudAsrHelper.writeBe32(out, 16, h4);
    CloudAsrHelper.writeBe32(out, 20, h5);
    CloudAsrHelper.writeBe32(out, 24, h6);
    CloudAsrHelper.writeBe32(out, 28, h7);
    return out;
  }

  // ---------------------- 纯 JS HMAC-SHA256 ----------------------
  public static hmacSha256(key: string, message: string): Uint8Array {
    const blockSize: number = 64;
    let keyBytes: Uint8Array = new util.TextEncoder().encode(key);
    if (keyBytes.byteLength > blockSize) {
      keyBytes = CloudAsrHelper.sha256(keyBytes);
    }
    const paddedKey: Uint8Array = new Uint8Array(blockSize);
    paddedKey.set(keyBytes);
    const ipad: Uint8Array = new Uint8Array(blockSize);
    const opad: Uint8Array = new Uint8Array(blockSize);
    for (let i: number = 0; i < blockSize; i++) {
      ipad[i] = paddedKey[i] ^ 0x36;
      opad[i] = paddedKey[i] ^ 0x5c;
    }
    const msgBytes: Uint8Array = new util.TextEncoder().encode(message);
    const inner: Uint8Array = new Uint8Array(blockSize + msgBytes.byteLength);
    inner.set(ipad);
    inner.set(msgBytes, blockSize);
    const innerHash: Uint8Array = CloudAsrHelper.sha256(inner);
    const outer: Uint8Array = new Uint8Array(blockSize + 32);
    outer.set(opad);
    outer.set(innerHash, blockSize);
    return CloudAsrHelper.sha256(outer);
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

  // 构造语音听写（IAT）WebSocket 鉴权地址（HMAC-SHA256，纯 ArkTS 实现）
  private static buildIatUrl(): string {
    const host: string = 'iat-api.xfyun.cn';
    const path: string = '/v2/iat';
    const date: string = new Date().toUTCString();
    const signatureOrigin: string =
      'host: ' + host + '\n' +
      'date: ' + date + '\n' +
      'GET ' + path + ' HTTP/1.1';
    const signBytes: Uint8Array = CloudAsrHelper.hmacSha256(XF_IAT_API_SECRET, signatureOrigin);
    const base64: util.Base64Helper = new util.Base64Helper();
    const signature: string = base64.encodeToStringSync(signBytes);
    const authorizationOrigin: string =
      'api_key="' + XF_IAT_API_KEY + '", algorithm="hmac-sha256", headers="host date request-line", signature="' + signature + '"';
    const authorization: string = base64.encodeToStringSync(new util.TextEncoder().encode(authorizationOrigin));
    return 'wss://' + host + path +
      '?authorization=' + encodeURIComponent(authorization) +
      '&date=' + encodeURIComponent(date) +
      '&host=' + encodeURIComponent(host);
  }

  // 把 WAV 文件通过讯飞语音听写（IAT）WebSocket 流式转成文字（免费额度，需开通「语音听写」服务）
  static transcribe(wavPath: string): Promise<string> {
    if (XF_IAT_API_KEY.startsWith('YOUR_')) {
      return Promise.reject(new Error('CloudAsrHelper 未配置语音听写密钥，请填入 XF_IAT_API_KEY / XF_IAT_API_SECRET'));
    }

    // 1) 读取 WAV，提取 PCM（跳过 44 字节头，要求 16k 单声道 16bit）
    let stat: fileIo.Stat;
    let file: fileIo.File;
    try {
      stat = fileIo.statSync(wavPath);
      file = fileIo.openSync(wavPath, fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      return Promise.reject(new Error('CloudAsrHelper 无法读取录音文件: ' + wavPath));
    }
    const total: number = stat.size;
    const allBuf: ArrayBuffer = new ArrayBuffer(total);
    try {
      fileIo.readSync(file.fd, allBuf);
    } finally {
      fileIo.closeSync(file.fd);
    }
    if (total <= 44) {
      return Promise.reject(new Error('CloudAsrHelper: 录音文件无有效数据'));
    }
    const pcm: Uint8Array = new Uint8Array(allBuf, 44, total - 44);

    // 2) 切成 ≤1280 字节的帧（16k 单声道 16bit，每帧约 40ms）
    const FRAME: number = 1280;
    const frames: ArrayBuffer[] = [];
    for (let off: number = 0; off < pcm.byteLength; off += FRAME) {
      const len: number = Math.min(FRAME, pcm.byteLength - off);
      const slice: Uint8Array = pcm.subarray(off, off + len);
      const ab: ArrayBuffer = new ArrayBuffer(len);
      new Uint8Array(ab).set(slice);
      frames.push(ab);
    }
    if (frames.length === 0) {
      return Promise.reject(new Error('CloudAsrHelper: 录音无音频数据'));
    }

    return new Promise<string>((resolve: (v: string) => void, reject: (e: Error) => void): void => {
      const ws = webSocket.createWebSocket();
      const base64Helper: util.Base64Helper = new util.Base64Helper();
      let result: string = '';
      let done: boolean = false;
      let idx: number = 0;

      const finish = (ok: boolean, text: string, errMsg?: string): void => {
        if (done) {
          return;
        }
        done = true;
        try {
          ws.close();
        } catch (e) { /* ignore */ }
        if (ok) {
          resolve(text);
        } else {
          reject(new Error(errMsg ?? '语音听写失败'));
        }
      };

      const sendFrame = (status: number, audio: ArrayBuffer): void => {
        const payload: IatFrame = {
          common: { app_id: XF_APP_ID } as IatCommon,
          business: { language: 'zh_cn', domain: 'iat', accent: 'mandarin', vad_eos: 1000 },
          data: {
            status: status,
            format: 'audio/L16;rate=16000',
            encoding: 'raw',
            audio: status === 2 ? '' : base64Helper.encodeToStringSync(new Uint8Array(audio))
          }
        };
        try {
          ws.send(JSON.stringify(payload));
        } catch (e) {
          finish(false, '', '语音听写发送失败: ' + ((e as BusinessError)?.message ?? String(e)));
        }
      };

      ws.on('open', (err: BusinessError, _value: Object): void => {
        if (err) {
          finish(false, '', '语音听写连接失败: ' + err.message);
          return;
        }
        sendFrame(0, frames[0]);
      });

      ws.on('message', (err: BusinessError, value: string | ArrayBuffer): void => {
        if (err) {
          finish(false, '', '语音听写接收失败: ' + err.message);
          return;
        }
        let str: string = '';
        if (typeof value === 'string') {
          str = value;
        } else {
          str = new util.TextDecoder().decodeToString(new Uint8Array(value as ArrayBuffer));
        }
        let resp: IatResp;
        try {
          resp = JSON.parse(str) as IatResp;
        } catch (e) {
          return;
        }
        if (resp.code !== 0) {
          finish(false, '', '语音听写错误(' + resp.code + '): ' + (resp.message ?? '未知'));
          return;
        }
        if (resp.data && resp.data.result && resp.data.result.ws) {
          for (const item of resp.data.result.ws) {
            if (item.cw && item.cw.length > 0) {
              result += item.cw[0].w;
            }
          }
        }
        if (resp.data && resp.data.status === 2) {
          finish(true, result);
          return;
        }
        idx++;
        if (idx < frames.length) {
          sendFrame(1, frames[idx]);
        } else {
          sendFrame(2, new ArrayBuffer(0));
        }
      });

      ws.on('error', (err: BusinessError): void => {
        finish(false, '', '语音听写出错: ' + err.message);
      });

      ws.on('close', (err: BusinessError, _value: Object): void => {
        if (!done) {
          if (result && result.length > 0) {
            finish(true, result);
          } else {
            finish(false, '', '语音听写连接提前关闭');
          }
        }
      });

      try {
        ws.connect(CloudAsrHelper.buildIatUrl(), (err: BusinessError, _value: Object): void => {
          if (err) {
            finish(false, '', '语音听写建立连接失败: ' + err.message);
          }
        });
      } catch (e) {
        finish(false, '', '语音听写连接异常: ' + ((e as BusinessError)?.message ?? String(e)));
      }
    });
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>(ok => setTimeout(ok, ms));
  }
}

// 端侧语音识别转写助手（Core Speech Kit · speechRecognizer）
// 作用：把本地 WAV(PCM 16k / 单声道 / 16bit) 录音文件转成文字，用于回访时对照逐字稿。
//
// API 约束（已核实，本工程 API 20 可用）：
//   - createEngine({ language:'zh-CN', online, extraParams:{ locate:'CN', recognizerMode:'long' } })
//   - setListener({ onStart, onResult, onError, onComplete })
//   - startListening({ sessionId,
//       audioInfo:{ audioType:'pcm', sampleRate:16000, soundChannel:1, sampleBit:16 },
//       extraParams:{ recognitionMode:1, maxAudioDuration:600000 } })
//   - 从 WAV 跳过 44 字节头 → 循环 read 640/1280 字节块 → writeAudio(sessionId, chunk)
//   - finish(sessionId) → shutdown()
//   - onResult 中 result.result 即文字；isFinal=true 为整句结束，据此累积成完整逐字稿。
//
// ⚠️ online 取值：Core Speech Kit 当前仅支持离线识别（online:1），不支持云侧。
//   离线模式需设备已下载「中文语音识别模型」（系统设置→智慧语音→离线识别模型）。
//   无模型时 createEngine 可能返回空引擎/报错；已加 15s 兜底超时杜绝无限"转写中"。
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0002;
const TAG: string = 'AsrHelper';

// WAV 文件头固定 44 字节（PCM 16bit 标准头），后面才是纯 PCM 数据，转写需跳过
const WAV_HEADER: number = 44;
// writeAudio 严格块长：取 1280（640 的整数倍，单块覆盖约 80ms 音频 @16k*2）
const CHUNK: number = 1280;
// 模拟语速写入节奏（每 40ms 写一块），防止引擎内部队列溢出
const WRITE_INTERVAL_MS: number = 40;
// 兜底超时（ms）：finish 后若识别异常导致 onComplete 不触发，最多再等这段时间用已得文字结算，杜绝无限转写中
const GUARD_MS: number = 15000;

class _AsrHelperImpl {
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private sessionId: string = 'asr_' + Date.now().toString();
  private resultText: string = '';      // 当前可见文字（已确认句 + 当前句中间结果）
  private committedText: string = '';   // 已整句确认(isFinal)累积的文字
  private lastInitErr: string = '';      // 最近一次 createEngine 失败信息（含错误码），用于上层提示
  private resolveFn: ((text: string) => void) | undefined = undefined;
  private rejectFn: ((err: string) => void) | undefined = undefined;
  private guardTimer: number = 0;        // 兜底定时器句柄
  private inflight: Promise<string> | null = null;  // 进行中的识别任务（并发去重，杜绝两路调用交叉写引擎）

  // 创建引擎（离线 long 模式，Core Speech Kit 仅支持离线）；已存在直接返回 true。
  // 返回 false 多在设备未下载/未启用中文语音识别离线模型时发生 → 需要去系统设置下载。
  private async ensureEngine(): Promise<boolean> {
    if (this.engine) return true;
    const extraParam: Record<string, Object> = {
      'locate': 'CN',
      'recognizerMode': 'long'   // 单题 150s > 60s 短语音上限，必须用 long（≤8h）
    };
    const initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,                 // Core Speech Kit 当前仅支持离线识别
      extraParams: extraParam
    };
    return new Promise<boolean>((resolve) => {
      speechRecognizer.createEngine(initParams, (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine) => {
        if (!err) {
          this.engine = engine;
          this.setListener();
          resolve(true);
        } else {
          this.lastInitErr = err.code + ':' + err.message;
          hilog.error(DOMAIN, TAG, 'createEngine fail: %{public}s', this.lastInitErr);
          resolve(false);
        }
      });
    });
  }

  // 注册监听：onResult 累积整句，onComplete 结算，onError 失败；均会释放引擎并清兜底定时器
  private setListener(): void {
    if (!this.engine) return;
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (_sid: string, _msg: string) => { /* 引擎就绪，无需处理 */ },
      onEvent: (_sid: string, _code: number, _msg: string) => { /* 内部事件（静音检测等），忽略 */ },
      onResult: (_sid: string, result: speechRecognizer.SpeechRecognitionResult) => {
        // isFinal=true 为整句结束，追加到已确认累积；否则为当前句的中间结果，仅拼接展示
        if (result.isFinal) {
          this.committedText += result.result;
          this.resultText = this.committedText;
        } else {
          this.resultText = this.committedText + result.result;
        }
      },
      onComplete: (_sid: string, _msg: string) => {
        this.clearGuard();
        const text: string = this.committedText.trim();
        if (this.resolveFn) {
          this.resolveFn(text);
          this.resolveFn = undefined;
          this.rejectFn = undefined;
        }
        this.shutdownEngine();
      },
      onError: (_sid: string, code: number, msg: string) => {
        this.clearGuard();
        const reason: string = `ASR 失败 ${code}: ${msg}`;
        hilog.error(DOMAIN, TAG, 'asr error: %{public}s', reason);
        if (this.rejectFn) {
          this.rejectFn(reason);
          this.resolveFn = undefined;
          this.rejectFn = undefined;
        }
        this.shutdownEngine();
      }
    };
    this.engine.setListener(listener);
  }

  private clearGuard(): void {
    if (this.guardTimer !== 0) {
      clearTimeout(this.guardTimer);
      this.guardTimer = 0;
    }
  }

  private shutdownEngine(): void {
    if (this.engine) {
      try { this.engine.shutdown(); } catch (e) { /* ignore */ }
      this.engine = undefined;
    }
  }

  // 文件转写：打开 WAV → 跳过 44 字节头 → startListening 启动识别 → 按 1280 字节块 writeAudio → finish → 返回文字
  async transcribeFile(wavPath: string): Promise<string> {
    // 并发去重：录音结束跳点评时，AudioAnswer 的转写与点评页兜底可能同时调用，共用同一 Promise 结果，
    // 避免两个 startListening/writeAudio 在同一引擎上交叉导致识别混乱或卡死
    if (this.inflight) return this.inflight;
    this.inflight = this.doTranscribe(wavPath).finally((): void => { this.inflight = null; });
    return this.inflight;
  }

  private async doTranscribe(wavPath: string): Promise<string> {
    const ok: boolean = await this.ensureEngine();
    if (!ok || !this.engine) {
      throw new Error('语音识别引擎初始化失败（' + this.lastInitErr +
        '）。Core Speech Kit 仅支持离线识别；若已在系统「设置→智慧语音」下载中文离线模型仍失败，多为本机缺失离线识别运行时（libhiai_ir_infershape.so，与系统镜像/小艺相关）。可改用「开口自测」页手动录入转写稿，或更换离线能力正常的设备重试。');
    }
    this.committedText = '';
    this.resultText = '';
    // 每次转写使用新的会话 ID，避免重复调用时 session 冲突导致 startListening 失败
    this.sessionId = 'asr_' + Date.now().toString() + '_' + Math.floor(Math.random() * 1000).toString();
    return new Promise<string>((resolve, reject) => {
      this.resolveFn = resolve;
      this.rejectFn = reject;
      try {
        const stat = fileIo.statSync(wavPath);
        const total: number = stat.size;
        if (total <= WAV_HEADER) {
          this.clearGuard();
          resolve('');
          return;
        }
        // recognitionMode:1 = 实时音频转文字（文件流需 writeAudio 喂入）；maxAudioDuration 放宽到 10 分钟覆盖单题作答
        const audioInfo: speechRecognizer.AudioInfo = {
          audioType: 'pcm',
          sampleRate: 16000,
          soundChannel: 1,
          sampleBit: 16
        };
        const extraParam: Record<string, Object> = {
          'recognitionMode': 1,
          'maxAudioDuration': 600000
        };
        const startParams: speechRecognizer.StartParams = {
          sessionId: this.sessionId,
          audioInfo: audioInfo,
          extraParams: extraParam
        };

        // ⚠️ 必须先 startListening 再 writeAudio，否则报 1002200010（未启动监听），音频被丢弃 → 转写无结果
        this.engine!.startListening(startParams);

        // 打开 WAV 文件；ArkTS fileIo 无 seekSync，跳过 44 字节头：先 readSync 吞掉头（读到临时 buffer 丢弃）
        const file = fileIo.openSync(wavPath, fileIo.OpenMode.READ_ONLY);
        const headerBuf: ArrayBuffer = new ArrayBuffer(WAV_HEADER);
        fileIo.readSync(file.fd, headerBuf, { offset: 0, length: WAV_HEADER }); // 吞掉 WAV 头，不使用

        const buf: ArrayBuffer = new ArrayBuffer(CHUNK);
        let bytesRead: number = 0;
        const sleep = (ms: number): Promise<void> => new Promise<void>((r) => setTimeout(r, ms));
        (async (): Promise<void> => {
          try {
            // 已跳过 44 字节头，从此处开始顺序读 PCM 数据，直到 EOF
            while ((bytesRead = fileIo.readSync(file.fd, buf, { offset: 0, length: CHUNK })) > 0) {
              // writeAudio 块长【仅支持 640 或 1280 字节】；最后一块不足 1280 时补零到 1280，否则报 401 参数错误
              let chunk: Uint8Array;
              if (bytesRead < CHUNK) {
                chunk = new Uint8Array(CHUNK);
                chunk.set(new Uint8Array(buf.slice(0, bytesRead)));
              } else {
                chunk = new Uint8Array(buf.slice(0, bytesRead));
              }
              this.engine!.writeAudio(this.sessionId, chunk);
              await sleep(WRITE_INTERVAL_MS);
            }
          } catch (e) {
            const err = e as BusinessError;
            hilog.error(DOMAIN, TAG, 'writeAudio loop fail: %{public}s', err.message);
          } finally {
            try { fileIo.closeSync(file.fd); } catch (closeErr) { /* ignore */ }
            // 写完所有音频（或读到 EOF）→ 结束识别，触发 onComplete 返回最终文字
            try { this.engine!.finish(this.sessionId); } catch (e) { /* ignore */ }
            // 兜底：若 finish 因异常未触发 onComplete，最多再等 GUARD_MS 用已得文字结算，绝不让"转写中"卡死
            this.clearGuard();
            this.guardTimer = setTimeout((): void => {
              this.guardTimer = 0;
              const partial: string = this.committedText.trim();
              if (this.resolveFn) {
                this.resolveFn(partial);
                this.resolveFn = undefined;
                this.rejectFn = undefined;
              }
              this.shutdownEngine();
            }, GUARD_MS);
          }
        })();
      } catch (e) {
        const err = e as BusinessError;
        this.clearGuard();
        hilog.error(DOMAIN, TAG, 'transcribeFile fail: %{public}s', err.message);
        reject(`读取失败: ${err.message}`);
      }
    });
  }

  // 释放引擎（页面销毁或不再需要时调用）
  release(): void {
    this.clearGuard();
    this.shutdownEngine();
  }
}

export const AsrHelper = new _AsrHelperImpl();

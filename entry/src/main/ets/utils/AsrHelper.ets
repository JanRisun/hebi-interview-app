// 端侧语音识别转写助手（Core Speech Kit · speechRecognizer）
// 作用：把本地 WAV(PCM 16k / 单声道 / 16bit) 录音文件转成文字，全程离线、零密钥、隐私不出本机。
// 用于「开口自测」环节：考生口述作答 → 本地转写 → 复盘时对照逐字稿找差距（卡顿/漏点/口头禅）。
// 为什么需要它：TTS 只是「听」，ASR 才是「说→文字」，二者互补，构成完整的开口练习闭环。
//
// API 约束（已核实 HarmonyOS 官方文档，本工程 API 20 可用）：
//   - 起始版本 API 11，离线模型可用，仅需 ohos.permission.MICROPHONE（RecorderBar 已申请）。
//   - 文件转文字：startListening 配 recognitionMode:0 + audioInfo{pcm,16000,1,16}；循环 writeAudio 喂 PCM 流。
//   - writeAudio 每次块长【仅支持 640 或 1280 字节】，否则识别率骤降甚至报错。
//   - 单题作答约 150s > 60s 短语音上限 → createEngine 必须 recognizerMode:'long'（≤8h）。
//   - 结果：onResult 回调中 result.result 为文字、result.isFinal=true 为最终完整结果；finish() 触发 onComplete。
//
// ⚠️ 输入格式要求：仅支持 WAV(PCM 16k/单声道/16bit)。当前录音用 AVRecorder(AAC/m4a)，
//   故实际链路为「录音(m4a) → 待实现解码(PCM) → 转写」；若后续切换到 OH Audio 录 PCM 则可直接喂入。
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

class _AsrHelperImpl {
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private sessionId: string = 'asr_' + Date.now().toString();
  private resultText: string = '';
  private resolveFn: ((text: string) => void) | undefined = undefined;
  private rejectFn: ((err: string) => void) | undefined = undefined;

  // 创建引擎（long 离线模式）；已存在直接返回
  private async ensureEngine(): Promise<void> {
    if (this.engine) return;
    const extraParam: Record<string, Object> = {
      'locate': 'CN',
      'recognizerMode': 'long'   // 单题 150s > 60s 短语音上限，必须用 long
    };
    const initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,                 // 1 = 离线模型
      extraParams: extraParam
    };
    return new Promise<void>((resolve) => {
      speechRecognizer.createEngine(initParams, (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine) => {
        if (!err) {
          this.engine = engine;
          this.setListener();
        } else {
          hilog.error(DOMAIN, TAG, 'createEngine fail: %{public}s', err.message);
        }
        resolve();
      });
    });
  }

  // 注册监听：结果生灭完全由 onResult/finish 管理
  private setListener(): void {
    if (!this.engine) return;
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (_sid: string, _msg: string) => { /* 引擎就绪，无需处理 */ },
      onEvent: (_sid: string, _code: number, _msg: string) => { /* 内部事件（静音检测等），忽略 */ },
      onResult: (_sid: string, result: speechRecognizer.SpeechRecognitionResult) => {
        // result.result 为当前已识别文字；isFinal=true 为最终完整结果
        this.resultText = result.result;
      },
      onComplete: (_sid: string, _msg: string) => {
        const text: string = this.resultText.trim();
        if (this.resolveFn) {
          this.resolveFn(text);
          this.resolveFn = undefined;
          this.rejectFn = undefined;
        }
      },
      onError: (_sid: string, code: number, msg: string) => {
        hilog.error(DOMAIN, TAG, 'asr error: %{public}d %{public}s', code, msg);
        if (this.rejectFn) {
          this.rejectFn(`ASR 失败 ${code}: ${msg}`);
          this.resolveFn = undefined;
          this.rejectFn = undefined;
        }
      }
    };
    this.engine.setListener(listener);
  }

  // 文件转写：打开 WAV → seek 跳过 44 字节头 → 循环 readSync 顺序读（每次自动推进 fd 位置）
  //   → 按 1280 字节块 writeAudio → finish() → 返回文字
  async transcribeFile(wavPath: string): Promise<string> {
    await this.ensureEngine();
    if (!this.engine) return '';
    this.resultText = '';
    return new Promise<string>((resolve, reject) => {
      this.resolveFn = resolve;
      this.rejectFn = reject;
      try {
        const stat = fileIo.statSync(wavPath);
        const total: number = stat.size;
        if (total <= WAV_HEADER) {
          resolve('');
          return;
        }
        // 开始识别（文件转文字模式 recognitionMode:0）
        const audioInfo: speechRecognizer.AudioInfo = {
          audioType: 'pcm',
          sampleRate: 16000,
          soundChannel: 1,
          sampleBit: 16
        };
        const extraParam: Record<string, Object> = {
          'recognitionMode': 0,
          'vadBegin': 2000,
          'vadEnd': 3000,
          'maxAudioDuration': 200000
        };
        const startParams: speechRecognizer.StartParams = {
          sessionId: this.sessionId,
          audioInfo: audioInfo,
          extraParams: extraParam
        };

        // 打开 WAV 文件
        // ArkTS fileIo 没有 seekSync 方法；跳过 44 字节头的做法：先 readSync 吞掉头（读到临时 buffer 丢弃）
        const file = fileIo.openSync(wavPath, fileIo.OpenMode.READ_ONLY);
        const headerBuf: ArrayBuffer = new ArrayBuffer(WAV_HEADER);
        fileIo.readSync(file.fd, headerBuf, { offset: 0, length: WAV_HEADER }); // 吞掉 WAV 头，不使用

        const buf: ArrayBuffer = new ArrayBuffer(CHUNK);
        // fileIo.readSync 返回 number（实际读到的字节数），参数：(fd, buffer, {offset, length})
        let bytesRead: number = 0;
        const sleep = (ms: number): Promise<void> => new Promise<void>((r) => setTimeout(r, ms));
        (async (): Promise<void> => {
          try {
            // 已跳过 44 字节头，从此处开始顺序读 PCM 数据，直到 EOF
            while ((bytesRead = fileIo.readSync(file.fd, buf, { offset: 0, length: CHUNK })) > 0) {
              this.engine!.writeAudio(this.sessionId, new Uint8Array(buf.slice(0, bytesRead)));
              await sleep(WRITE_INTERVAL_MS);
            }
          } catch (e) {
            const err = e as BusinessError;
            hilog.error(DOMAIN, TAG, 'writeAudio loop fail: %{public}s', err.message);
          } finally {
            try { fileIo.closeSync(file.fd); } catch (closeErr) { /* ignore */ }
            // 写完所有音频（或读到 EOF）→ 结束识别，触发 onComplete 返回最终文字
            this.engine!.finish(this.sessionId);
          }
        })();
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'transcribeFile fail: %{public}s', err.message);
        reject(`读取失败: ${err.message}`);
      }
    });
  }

  // 释放引擎（页面销毁或不再需要时调用）
  release(): void {
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (e) { /* ignore */ }
      this.engine = undefined;
    }
  }
}

export const AsrHelper = new _AsrHelperImpl();

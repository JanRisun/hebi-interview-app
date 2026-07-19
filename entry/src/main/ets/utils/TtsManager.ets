// 文本转语音（TTS）单例管理器
// 文档明确：Core Speech Kit 的 TTS 引擎为「单应用单实例」，故全局只建一个引擎，所有页面共用。
// 能力来自 @kit.CoreSpeechKit，纯本地离线合成，无需麦克风权限。
// 适用版本：API 7 起支持文本转语音；本工程 API 20 可用。
// V2 增量：暂停/继续、倍速调节（0.5x ~ 1.5x）、AppStorage 全局态同步
import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 倍速选项（与学习强国对齐）
export const SPEED_OPTIONS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5];
export const SPEED_LABELS: string[] = ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x'];

class _TtsEngineImpl {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private playing: boolean = false;     // 是否正在播报（含暂停前的播放态）
  private paused: boolean = false;      // 是否处于暂停状态
  private currentText: string = '';    // 过滤后文本（用于 toggle 同段判定）
  private rawText: string = '';        // 原始文本（用于 UI 高亮「正在朗读的是哪段」）
  private _speed: number = 1.0;       // 当前倍速（默认 1.0x）

  get speed(): number {
    return this._speed;
  }

  set speed(v: number) {
    this._speed = v;
    AppStorage.setOrCreate('ttsSpeed', v);
  }

  get isPaused(): boolean {
    return this.paused;
  }

  get isPlaying(): boolean {
    return this.playing && !this.paused;
  }

  // 创建引擎（异步，单例）；已存在直接返回
  private ensureEngine(): Promise<void> {
    return new Promise<void>((resolve) => {
      if (this.engine) {
        resolve();
        return;
      }
      const extraParam: Record<string, Object> = {
        'style': 'interaction-broadcast',
        'locate': 'CN',
        'name': 'EngineName'
      };
      const initParams: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,            // 0 = 聆小珊女声
        online: 1,            // 1 = 离线模式（当前仅支持离线）
        extraParams: extraParam
      };
      textToSpeech.createEngine(initParams, (err: BusinessError, engine: textToSpeech.TextToSpeechEngine) => {
        if (!err) {
          this.engine = engine;
        } else {
          console.error(`TTS createEngine failed: ${err.code} ${err.message}`);
        }
        resolve();
      });
    });
  }

  // 朗读一段文本；同一引擎实例 requestId 只能用一次，每次 speak 必须生成新 ID
  async speak(text: string): Promise<void> {
    const t: string = this.filterText(text);
    if (!t) {
      return;
    }
    this.rawText = text;
    await this.ensureEngine();
    if (!this.engine) {
      return;
    }
    this.engine.stop();
    this.playing = true;
    this.paused = false;
    this.currentText = t;
    this.syncState();
    const speakParams: textToSpeech.SpeakParams = {
      requestId: 'tts_' + Date.now().toString(),
      extraParams: {
        'queueMode': 0,
        'speed': this._speed,
        'volume': 2,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'soundChannel': 3,
        'playType': 1
      } as Record<string, Object>
    };
    this.engine.setListener({
      onStart: (_requestId: string, _response: textToSpeech.StartResponse) => {
        this.syncState(); // 播放开始时同步状态
      },
      onComplete: (_requestId: string, _response: textToSpeech.CompleteResponse) => {
        this.playing = false;
        this.paused = false;
        this.syncState();
      },
      onStop: (_requestId: string, _response: textToSpeech.StopResponse) => {
        this.playing = false;
        this.paused = false;
        this.syncState();
      },
      onData: (_requestId: string, _audio: ArrayBuffer, _response: textToSpeech.SynthesisResponse) => {
        // 默认 playType=1 不返回音频流，此处留空
      },
      onError: (_requestId: string, code: number, message: string) => {
        console.error(`TTS error: ${code} ${message}`);
        this.playing = false;
        this.paused = false;
        this.syncState();
      }
    });
    this.engine.speak(t, speakParams);
  }

  // 暂停播报（API 10+ 引擎原生 pause，回退用 stop 模拟）
  pause(): void {
    if (!this.isPlaying || !this.engine) return;
    try {
      // 尝试调用引擎原生 pause [API 10+]
      (this.engine as ESObject).pause?.();
    } catch (e) {
      // 回退：stop + 标记暂停态（恢复时重新 speak）
      this.engine!.stop();
    }
    this.paused = true;
    this.syncState();
  }

  // 继续播报（从暂停处恢复；若引擎无原生 resume 则重新 speak 当前文本）
  async resume(): Promise<void> {
    if (!this.playing || !this.paused) return;
    this.paused = false;
    this.syncState();
    try {
      // 尝试调用引擎原生 resume [API 10+]
      if ((this.engine as ESObject).resume) {
        (this.engine as ESObject).resume();
        return;
      }
    } catch (e) {
      // fall through 到 re-speak
    }
    // 无原生 resume → 用当前文本重新 speak（会从头开始，但保证可用）
    if (this.currentText) {
      await this.speak(this.rawText);
    }
  }

  // 切换：同一文本正在播则暂停/停止，否则开始播报
  async toggle(text: string): Promise<void> {
    const t: string = this.filterText(text);
    if (this.currentText === t && this.playing) {
      // 同一段文本：播放中→暂停，暂停中→继续
      if (this.paused) {
        await this.resume();
      } else {
        this.pause();
      }
    } else {
      // 不同文本或未在播：停止当前 → 开始新播报
      await this.speak(text);
    }
  }

  stop(): void {
    if (this.engine) {
      this.engine.stop();
    }
    this.playing = false;
    this.paused = false;
    this.syncState();
  }

  // 切换倍速（循环切换 SPEED_OPTIONS）
  cycleSpeed(): void {
    const idx: number = SPEED_OPTIONS.indexOf(this._speed);
    const nextIdx: number = (idx + 1) % SPEED_OPTIONS.length;
    this.speed = SPEED_OPTIONS[nextIdx];
    // 如果正在播报，以新倍速重新朗读当前内容
    if (this.isPlaying && this.rawText) {
      this.speak(this.rawText);
    }
  }

  // 同步全部状态到 AppStorage（供 UI 全局消费）
  private syncState(): void {
    AppStorage.setOrCreate('ttsPlaying', this.playing);
    AppStorage.setOrCreate('ttsPaused', this.paused);
    AppStorage.setOrCreate('ttsText', this.rawText);
    AppStorage.setOrCreate('ttsSpeed', this._speed);
  }

  // 移除表情符号等不可朗读字符，避免合成异常或乱读
  private filterText(text: string): string {
    if (!text) {
      return '';
    }
    return text
      .replace(/[★☆⭐✓✗]/g, '')       // 常见 BMP 符号
      .replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, '') // 代理对 emoji
      .replace(/\s+/g, ' ')
      .trim();
  }

  // 页面销毁时释放引擎，避免资源泄漏
  shutdown(): void {
    if (this.engine) {
      this.engine.shutdown();
      this.engine = null;
    }
    this.playing = false;
    this.paused = false;
    this.syncState();
  }
}

export const TtsManager = new _TtsEngineImpl();

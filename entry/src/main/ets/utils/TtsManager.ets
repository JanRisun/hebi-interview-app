// 文本转语音（TTS）单例管理器
// 文档明确：Core Speech Kit 的 TTS 引擎为「单应用单实例」，故全局只建一个引擎，所有页面共用。
// 能力来自 @kit.CoreSpeechKit，纯本地离线合成，无需麦克风权限。
// 适用版本：API 7 起支持文本转语音；本工程 API 20 可用。
import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

class _TtsEngineImpl {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private playing: boolean = false;
  private currentText: string = '';   // 过滤后文本（用于 toggle 同段判定）
  private rawText: string = '';      // 原始文本（用于 UI 高亮「正在朗读的是哪段」）

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
    this.rawText = text;   // 记录原始文本，供 UI 高亮判定
    await this.ensureEngine();
    if (!this.engine) {
      return;
    }
    this.engine.stop();
    const speakParams: textToSpeech.SpeakParams = {
      requestId: 'tts_' + Date.now().toString(),
      extraParams: {
        'queueMode': 0,
        'speed': 1,
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
        this.playing = true;
        this.currentText = t;
        AppStorage.set('ttsPlaying', true);
        AppStorage.set('ttsText', this.rawText);
      },
      onComplete: (_requestId: string, _response: textToSpeech.CompleteResponse) => {
        this.playing = false;
        AppStorage.set('ttsPlaying', false);
        AppStorage.set('ttsText', '');
      },
      onStop: (_requestId: string, _response: textToSpeech.StopResponse) => {
        this.playing = false;
        AppStorage.set('ttsPlaying', false);
        AppStorage.set('ttsText', '');
      },
      onData: (_requestId: string, _audio: ArrayBuffer, _response: textToSpeech.SynthesisResponse) => {
        // 默认 playType=1 不返回音频流，此处留空
      },
      onError: (_requestId: string, code: number, message: string) => {
        console.error(`TTS error: ${code} ${message}`);
        this.playing = false;
        AppStorage.set('ttsPlaying', false);
        AppStorage.set('ttsText', '');
      }
    });
    this.engine.speak(t, speakParams);
  }

  // 切换：同一文本正在播则停止，否则开始播报
  async toggle(text: string): Promise<void> {
    const t: string = this.filterText(text);
    if (this.playing && this.currentText === t) {
      this.stop();
    } else {
      await this.speak(t);
    }
  }

  stop(): void {
    if (this.engine) {
      this.engine.stop();
    }
    this.playing = false;
    AppStorage.set('ttsPlaying', false);
    AppStorage.set('ttsText', '');
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
    AppStorage.set('ttsPlaying', false);
    AppStorage.set('ttsText', '');
  }
}

export const TtsManager = new _TtsEngineImpl();

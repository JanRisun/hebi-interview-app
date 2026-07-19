// 文本转语音（TTS）单例管理器
// 文档：Core Speech Kit 的 TTS 引擎为「单应用单实例」，故全局只建一个引擎，所有页面共用。
// 能力来自 @kit.CoreSpeechKit，纯本地离线合成，无需麦克风权限。适用版本：API 7 起，本工程 API 20 可用。
//
// 关键约束（本次重写重点）：
//  ① 本项目用的是 @kit.CoreSpeechKit 的 textToSpeech，其 TextToSpeechEngine 没有原生 pause/resume
//     （原生 pause/resume 仅存在于另一套 @ohos.speech.tts 旧 API）。因此「暂停/继续」用
//     「按句切分 + 记录句下标」自实现：暂停=停引擎并记住当前句，继续=从句首重新合成当前句
//     （句子级续播，等同学习强国体验——不从头重来）。
//  ② speak() 内部【严禁】先调 engine.stop()：那会异步触发 onStop 把状态置 false，
//     导致悬浮按钮闪退（用户 issue#3）。打断上一句靠 speakParams.queueMode=0（FLUSH）即可。
//  ③ onStop 改为纯空操作：会话的生/灭完全由 speak/pause/resume/stop/onComplete 显式管理，
//     不受异步回调干扰，从根上消除「闪一下就消失」。
import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 倍速选项（与学习强国对齐）
export const SPEED_OPTIONS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5];
export const SPEED_LABELS: string[] = ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x'];

class _TtsEngineImpl {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private sessionActive: boolean = false;   // 有朗读会话进行中（含「已暂停」）
  private playing: boolean = false;          // 正在出声（未暂停）
  private paused: boolean = false;           // 已暂停（会话仍在，可继续）
  private rawText: string = '';            // 原始文本（用于 UI 高亮「正在朗读的是哪段」）
  private currentText: string = '';        // 过滤后文本（用于 toggle 同段判定）
  private _speed: number = 1.0;           // 当前倍速（默认 1.0x）
  private sentences: string[] = [];        // 按句切分后的文本数组
  private segIndex: number = 0;           // 当前朗读到的句子下标

  get speed(): number {
    return this._speed;
  }

  set speed(v: number) {
    this._speed = v;
    AppStorage.setOrCreate('ttsSpeed', v);
  }

  get isPlaying(): boolean {
    return this.sessionActive && !this.paused;
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
          this.setListener();
        } else {
          console.error(`TTS createEngine failed: ${err.code} ${err.message}`);
        }
        resolve();
      });
    });
  }

  // 按中英文句末标点切分，便于「句子级暂停/继续」
  private splitSentences(text: string): string[] {
    if (!text) return [];
    const delims: string = '。！？!?\n';
    const out: string[] = [];
    let buf: string = '';
    for (let i = 0; i < text.length; i++) {
      const ch: string = text[i];
      buf += ch;
      if (delims.indexOf(ch) >= 0) {
        const s: string = buf.trim();
        if (s) out.push(s);
        buf = '';
      }
    }
    const tail: string = buf.trim();
    if (tail) out.push(tail);
    return out.length > 0 ? out : [text];
  }

  // 朗读一段文本（从头开始）
  async speak(text: string): Promise<void> {
    const t: string = this.filterText(text);
    if (!t) {
      return;
    }
    this.rawText = text;
    this.currentText = t;
    this.sentences = this.splitSentences(t);
    this.segIndex = 0;
    await this.ensureEngine();
    if (!this.engine) {
      return;
    }
    // 注意：此处【不】调用 engine.stop()，靠 queueMode=0(FLUSH) 打断上一句，
    // 避免异步 onStop 把会话状态错误清空（用户 issue#3 根因）。
    this.sessionActive = true;
    this.playing = true;
    this.paused = false;
    this.syncState();
    this.speakSegment();
  }

  // 朗读当前句（sentences[segIndex]）
  private speakSegment(): void {
    if (this.segIndex >= this.sentences.length) {
      this.finishSession();
      return;
    }
    if (!this.engine) {
      return;
    }
    const seg: string = this.sentences[this.segIndex];
    const speakParams: textToSpeech.SpeakParams = {
      requestId: 'tts_' + Date.now().toString() + '_' + this.segIndex.toString(),
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
    this.engine.speak(seg, speakParams);
  }

  // 本段全部读完 → 结束会话
  private finishSession(): void {
    this.sessionActive = false;
    this.playing = false;
    this.paused = false;
    this.segIndex = 0;
    this.syncState();
  }

  // 暂停：停引擎 + 记住当前句（onStop 空操作，不会清场）
  pause(): void {
    if (!this.playing || !this.engine) return;
    this.paused = true;
    this.playing = false;
    this.syncState();
    try {
      this.engine.stop();
    } catch (e) {
      // ignore
    }
    // 不重置 paused：保持「已暂停、可继续」语义
  }

  // 继续：从句首重新合成当前句 → 句子级续播（不从头重来）
  async resume(): Promise<void> {
    if (!this.sessionActive || !this.paused || !this.engine) return;
    this.paused = false;
    this.playing = true;
    this.syncState();
    this.speakSegment();
  }

  // 切换：同一文本正在播则暂停/继续，否则开始新播报
  async toggle(text: string): Promise<void> {
    const t: string = this.filterText(text);
    if (this.currentText === t && this.sessionActive) {
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
      try {
        this.engine.stop();
      } catch (e) {
        // ignore
      }
    }
    this.sessionActive = false;
    this.playing = false;
    this.paused = false;
    this.segIndex = 0;
    this.syncState();
  }

  // 切换倍速（循环切换 SPEED_OPTIONS）；若正在朗读，立即以新语速重读当前句
  cycleSpeed(): void {
    const idx: number = SPEED_OPTIONS.indexOf(this._speed);
    const nextIdx: number = (idx + 1) % SPEED_OPTIONS.length;
    this.speed = SPEED_OPTIONS[nextIdx];
    if (this.playing && this.engine) {
      this.speakSegment();
    }
  }

  // 注册监听：状态生灭完全由本类显式管理，onStop 不碰状态
  private setListener(): void {
    if (!this.engine) return;
    this.engine.setListener({
      onStart: (_requestId: string, _response: textToSpeech.StartResponse) => {
        this.syncState();
      },
      onComplete: (_requestId: string, _response: textToSpeech.CompleteResponse) => {
        if (!this.sessionActive) return;
        this.segIndex++;
        this.speakSegment();
      },
      onStop: (_requestId: string, _response: textToSpeech.StopResponse) => {
        // 空操作：stop/pause 调用方已自行管理状态，避免异步回调污染
      },
      onData: (_requestId: string, _audio: ArrayBuffer, _response: textToSpeech.SynthesisResponse) => {
        // 默认 playType=1 不返回音频流，此处留空
      },
      onError: (_requestId: string, code: number, message: string) => {
        console.error(`TTS error: ${code} ${message}`);
        if (!this.sessionActive) return;
        this.segIndex++;
        if (this.segIndex < this.sentences.length) {
          this.speakSegment();
        } else {
          this.finishSession();
        }
      }
    });
  }

  // 同步全部状态到 AppStorage（供 UI 全局消费）
  private syncState(): void {
    AppStorage.setOrCreate('ttsPlaying', this.sessionActive);
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

  // 是否有「上一段」可重播（供空闲态悬浮按钮使用）
  get hasLast(): boolean {
    return this.rawText.length > 0;
  }

  // 重播上一段（空闲态悬浮按钮点击时调用）
  async replayLast(): Promise<void> {
    if (this.rawText) {
      await this.speak(this.rawText);
    }
  }

  // 页面销毁时释放引擎，避免资源泄漏
  shutdown(): void {
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (e) {
        // ignore
      }
      this.engine = null;
    }
    this.sessionActive = false;
    this.playing = false;
    this.paused = false;
    this.syncState();
  }
}

export const TtsManager = new _TtsEngineImpl();

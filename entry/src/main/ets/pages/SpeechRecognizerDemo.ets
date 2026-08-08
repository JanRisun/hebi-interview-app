// 语音识别演示（CoreSpeechKit.speechRecognizer）：麦克风实时采集 PCM，
// 喂给识别引擎，实时显示识别文字（含中间结果 + 最终结果）。基于官方 SpeechRecognizer 能力指南实现。
//
// 权限：ohos.permission.MICROPHONE（已在 module.json5 声明）。
// 注意：在线识别（online:1，云端）无需下载离线模型；但需设备联网并登录华为账号（云侧服务授权）。
// 若在线失败且无离线模型，引擎可能静默出空结果——此时可到系统设置下载中文离线识别模型后改用 online:0。
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import bundleManager from '@ohos.bundle.bundleManager';
import { promptAction } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { BackHeader } from '../utils/BackHeader';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

const CHUNK: number = 1280; // writeAudio 严格块长（640 的整数倍，单块约 80ms @16k*2）

@Component
export struct SpeechRecognizerDemoView {
  @Consume pageStack: NavPathStack;
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  @State recognizing: boolean = false;        // 是否识别中（UI）
  @State resultText: string = '';             // 已确认的累积文本
  @State partialText: string = '';            // 当前中间结果
  @State status: string = '点击「开始识别」，对着麦克风说话';
  @State startFired: boolean = false;          // onStart 是否触发（引擎是否真正开始）
  @State resultCount: number = 0;              // onResult 回调次数（含中间/最终）
  @State partialCount: number = 0;             // 中间结果次数
  @State finalCount: number = 0;               // 最终结果次数
  @State writeFails: number = 0;               // writeAudio 抛异常的次数
  @State firstResultText: string = '';         // 第一次 onResult 的原文（即使空），便于诊断
  @State audioChunks: number = 0;              // readData 收到的音频块数（区分静音 vs 引擎问题）

  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private sessionId: string = '';
  private audioCapturer: audio.AudioCapturer | undefined = undefined;
  private asrReady: boolean = false;           // 引擎 onStart 后为真，才能喂音频

  aboutToAppear(): void {
    this.initEngine();
  }

  aboutToDisappear(): void {
    this.releaseAll();
  }

  private releaseAll(): void {
    this.recognizing = false;
    this.asrReady = false;
    if (this.audioCapturer) {
      try {
        this.audioCapturer.off('readData');
        this.audioCapturer.stop();
        this.audioCapturer.release();
      } catch (e) {
        // 忽略释放异常
      }
      this.audioCapturer = undefined;
    }
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (e) {
        // 忽略
      }
      this.engine = undefined;
    }
  }

  // 当前展示文字（已确认 + 中间结果）
  private displayText(): string {
    return this.resultText + this.partialText;
  }

  private wordCount(): number {
    const s: string = this.displayText().trim();
    return s.length === 0 ? 0 : s.length;
  }

  // 创建识别引擎（回调式，确保 this.engine 在 start 前就绪）
  private initEngine(): void {
    const extraParams: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'long' };
    const initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,                   // 在线（云端）识别，无需离线模型；需设备联网并登录华为账号
      extraParams: extraParams
    };
    this.status = '正在创建识别引擎…';
    // 必须包 try/catch：online:0 在离线模型缺失时会同步抛异常（不进入 err 回调），不捕获则 this.engine 永远 undefined
    try {
      speechRecognizer.createEngine(initParams, (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine): void => {
        if (err) {
          this.status = `引擎创建失败(${err.code}): ${err.message}（离线模型可能未下载，请到系统设置→智慧语音→离线识别模型下载中文模型）`;
          return;
        }
        this.engine = engine;
        this.setListener(engine);
        this.status = '引擎就绪，点击「开始识别」对着麦克风说话';
      });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.status = `引擎创建异常(${err.code}): ${err.message}（离线模型可能未下载）`;
    }
  }

  private setListener(engine: speechRecognizer.SpeechRecognitionEngine): void {
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (_sid: string, _msg: string): void => {
        this.asrReady = true;
        this.startFired = true;
      },
      onEvent: (_sid: string, _code: number, _msg: string): void => {
        // 内部事件（静音检测等），忽略
      },
      onResult: (_sid: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        this.resultCount++;
        if (result.isFinal) {
          this.finalCount++;
        } else {
          this.partialCount++;
        }
        if (this.firstResultText.length === 0) {
          this.firstResultText = JSON.stringify({
            isFinal: result.isFinal,
            len: (result.result ?? '').length,
            text: result.result ?? ''
          });
        }
        const txt: string = result.result ?? '';
        if (result.isFinal) {
          // final 文本可能为空（句末定界符），此时把最后一次中间结果作为该句落盘
          this.resultText += (txt.length > 0) ? txt : this.partialText;
          this.partialText = '';
        } else {
          this.partialText = txt;
        }
      },
      onComplete: (_sid: string, _msg: string): void => {
        // 收尾：若还有未落盘的中间结果，并入正式文本
        if (this.partialText.length > 0) {
          this.resultText += this.partialText;
          this.partialText = '';
        }
        // 若用户仍在识别中（没点停止），引擎可能因一句结束/VAD 而自动 onComplete —— 自动续接下一次会话
        if (this.recognizing && this.engine && this.sessionId) {
          try {
            this.asrReady = false;
            this.engine.startListening({
              sessionId: this.sessionId,
              audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 }
            });
            this.status = this.resultText.length > 0
              ? `继续识别中…（已识别 ${this.wordCount()} 字）`
              : '识别中…请说话';
          } catch (e) {
            const err: BusinessError = e as BusinessError;
            this.recognizing = false;
            this.asrReady = false;
            this.status = `续接会话失败(${err.code}): ${err.message}`;
          }
          return;
        }
        // 用户已点停止：进入"识别完成"态
        this.recognizing = false;
        this.asrReady = false;
        this.status = this.resultText.length > 0
          ? `识别完成，共 ${this.wordCount()} 字`
          : `未识别到文字（onStart=${this.startFired ? '✓' : '✗'} audio=${this.audioChunks}块 partial=${this.partialCount} final=${this.finalCount} writeFail=${this.writeFails}）。` +
            `在线识别需：①设备已联网；②已登录华为账号（云侧服务授权）。请确认这两项后重试；若仍为空，可到系统「设置」下载中文离线识别模型后再试。`;
      },
      onError: (_sid: string, code: number, msg: string): void => {
        this.status = `识别错误(${code}): ${msg}（onStart=${this.startFired ? '已触发' : '未触发'}）`;
        this.stopInternal();
      }
    };
    engine.setListener(listener);
  }

  // 开始识别：启动引擎 + 麦克风采集，把 PCM 块喂给引擎
  private onStart(): void {
    if (!this.engine) {
      // 引擎未就绪（首次进入页面/上轮创建失败）→ 重新尝试创建，不让用户必须退出重进
      this.initEngine();
      this.status = '引擎尚未就绪，正在重新创建…';
      return;
    }
    this.sessionId = `asr_${Date.now()}`;
    this.startFired = false;
    this.resultCount = 0;
    this.partialCount = 0;
    this.finalCount = 0;
    this.writeFails = 0;
    this.firstResultText = '';
    this.audioChunks = 0;
    const audioInfo: speechRecognizer.AudioInfo = {
      audioType: 'pcm',
      sampleRate: 16000,
      soundChannel: 1,
      sampleBit: 16
    };
    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: audioInfo
    };
    try {
      this.engine.startListening(startParams);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.status = `启动失败(${err.code}): ${err.message}`;
      return;
    }
    this.recognizing = true;
    this.status = '识别中…请说话';
    this.startCapturer();
  }

  // 麦克风采集配置（16k / 单声道 / 16bit PCM），按块读到即喂给引擎
  private async startCapturer(): Promise<void> {
    // ① 确认麦克风权限：先预检真实状态，已授权直接进入；未确定则弹窗申请；被永久拒绝给出指引
    const granted: boolean = await this.ensureMicPermission();
    if (!granted) {
      this.recognizing = false;
      return; // 状态文案已在 ensureMicPermission 内设置
    }
    // ② 创建并启动采集器
    try {
      this.audioCapturer = await audio.createAudioCapturer({
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
      });
      // 必须先注册 readData 回调，再 start()——否则采集启动后回调不会触发（audio 一直为 0）
      this.audioCapturer.on('readData', (buffer: ArrayBuffer): void => {
        this.feedAudio(buffer);
      });
      await this.audioCapturer.start();
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.status = `麦克风打开失败(${err.code}): ${err.message}`;
      this.recognizing = false;
      return;
    }
  }

  // 预检 + 申请麦克风权限；把真实授权状态打到状态栏，避免「静默不弹窗」让你无从判断
  private async ensureMicPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    // 1) 先读当前真实授权状态
    let curStatus: number = -1;
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      curStatus = await atManager.checkAccessToken(bundleInfo.appInfo.accessTokenId, 'ohos.permission.MICROPHONE');
    } catch (e) {
      // 预检失败不致命，继续走申请流程
    }
    if (curStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      this.status = '麦克风已授权，开始采集…';
      return true;
    }
    // 2) 未授权 → 弹窗申请（已拒绝且「不再询问」时系统不会弹窗，直接走下面分支）
    try {
      const perm = await atManager.requestPermissionsFromUser(ctx, ['ohos.permission.MICROPHONE']);
      if (perm.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        this.status = '麦克风已授权，开始采集…';
        return true;
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.status = `权限申请异常(${err.code}): ${err.message}`;
      return false;
    }
    // 3) 仍被拒绝（含「不再询问」）：系统不会再弹窗，引导去设置手动开启
    this.status = '麦克风权限未授权。若未出现弹窗，说明你此前已拒绝并勾选「不再询问」——请到系统' +
      '「设置 → 应用 → 面试上岸 → 权限 → 麦克风」手动开启后，重新进入本页重试。';
    return false;
  }

  // 把 PCM 块按 1280 字节切片喂给引擎（writeAudio 仅支持 640/1280，末块补零）；
  // 必须在 startListening 成功（onStart → asrReady）后才能调用，否则报 1002200010。
  private feedAudio(buffer: ArrayBuffer): void {
    if (!this.recognizing || !this.engine || !this.sessionId) {
      return;
    }
    if (!buffer || buffer.byteLength <= 0) {
      return;
    }
    // 无论引擎是否就绪都先计数，确保诊断行能反映「麦克风是否在采集」
    this.audioChunks++;
    if (!this.asrReady) {
      return;
    }
    const full: Uint8Array = new Uint8Array(buffer);
    for (let off: number = 0; off < full.length; off += CHUNK) {
      const end: number = Math.min(off + CHUNK, full.length);
      // 关键：必须复制成独立数组再喂。readData 的 buffer 是框架复用的，
      // 若用 subarray（零拷贝视图）直接喂，回调返回后缓冲区可能被复用/清零，
      // 引擎实际收到静音/乱码 → 只出空结果。
      const chunk: Uint8Array = new Uint8Array(CHUNK);
      chunk.set(full.subarray(off, end));
      try {
        this.engine.writeAudio(this.sessionId, chunk);
      } catch (e) {
        this.writeFails++;
        // 个别块写入失败忽略，继续后续音频
      }
    }
  }

  private onStop(): void {
    this.stopInternal();
    this.status = this.resultText.length > 0 ? '已停止' : '已停止（本次无识别结果）';
  }

  private stopInternal(): void {
    this.recognizing = false;
    this.asrReady = false;
    if (this.engine && this.sessionId) {
      try {
        this.engine.finish(this.sessionId);
      } catch (e) {
        // 忽略
      }
    }
    if (this.audioCapturer) {
      try {
        this.audioCapturer.off('readData');
        this.audioCapturer.stop();
        this.audioCapturer.release();
      } catch (e) {
        // 忽略
      }
      this.audioCapturer = undefined;
    }
  }

  private onClear(): void {
    this.resultText = '';
    this.partialText = '';
    this.startFired = false;
    this.resultCount = 0;
    this.partialCount = 0;
    this.finalCount = 0;
    this.writeFails = 0;
    this.firstResultText = '';
    this.audioChunks = 0;
    this.status = '已清空，点击「开始识别」重新说';
  }

  private onCopy(): void {
    const text: string = this.displayText();
    if (text.length === 0) {
      promptAction.showToast({ message: '暂无内容可复制', duration: 1500 });
      return;
    }
    const sysBoard = pasteboard.getSystemPasteboard();
    sysBoard.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
    promptAction.showToast({ message: '已复制到剪贴板', duration: 1500 });
  }

  build() {
    Column() {
      BackHeader({ title: '语音识别', showAction: false })

      // 状态卡片（含录音指示）
      Column() {
        Row({ space: SPACE.sm }) {
          // 录音指示点
          Stack() {
            if (this.recognizing) {
              Circle()
                .width(18)
                .height(18)
                .fill($r('app.color.danger'))
                .opacity(0.25)
                .animation({ duration: 900, iterations: -1, playMode: PlayMode.Alternate })
            }
            Circle()
              .width(12)
              .height(12)
              .fill(this.recognizing ? $r('app.color.danger') : $r('app.color.text_tertiary'))
          }
          .width(20)
          .height(20)

          Text(this.status)
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .alignSelf(ItemAlign.Center)
        }
        .width('100%')
        Text(`诊断：onStart=${this.startFired ? '✓' : '✗'}  audio=${this.audioChunks}块  onResult=${this.resultCount}(p${this.partialCount}/f${this.finalCount})  writeFail=${this.writeFails}`)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: SPACE.xs })
          .width('100%')
        if (this.firstResultText.length > 0) {
          Text(`首条结果：${this.firstResultText}`)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: SPACE.xs })
            .width('100%')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .padding(SPACE.md)
      .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.sm })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.lg)

      // 识别结果卡片
      Column() {
        Row({ space: SPACE.sm }) {
          Text('识别结果')
            .fontSize(FONT.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.wordCount() > 0 ? `${this.wordCount()} 字` : '')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .margin({ bottom: SPACE.sm })

        Scroll() {
          Column() {
            Text(this.displayText())
              .fontSize(FONT.title)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(FONT.title * 1.6)
              .width('100%')
            if (this.displayText().length === 0) {
              Text('等待识别…对着麦克风说话后，文字会实时显示在这里')
                .fontSize(FONT.bodySm)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .padding(SPACE.md)
      .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.sm })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.lg)

      // 操作区
      Row({ space: SPACE.sm }) {
        Button(this.recognizing ? '停止识别' : '开始识别')
          .height(44)
          .layoutWeight(1)
          .borderRadius(RADIUS.pill)
          .backgroundColor(this.recognizing ? $r('app.color.danger') : $r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .fontSize(FONT.body)
          .onClick(() => {
            if (this.recognizing) {
              this.onStop();
            } else {
              this.onStart();
            }
          })
        Button('清空')
          .height(44)
          .width(80)
          .borderRadius(RADIUS.pill)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.text_primary'))
          .fontSize(FONT.body)
          .onClick(() => this.onClear())
        Button('复制')
          .height(44)
          .width(80)
          .borderRadius(RADIUS.pill)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.text_primary'))
          .fontSize(FONT.body)
          .onClick(() => this.onCopy())
      }
      .width('100%')
      .padding({ left: SPACE.md, right: SPACE.md, bottom: this.safeBottom + SPACE.lg, top: SPACE.sm })
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop })
  }
}

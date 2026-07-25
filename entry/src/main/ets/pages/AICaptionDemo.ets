// AI 实时字幕演示页：基于 HarmonyOS SpeechKit 的 AICaptionComponent，
// 麦克风实时采集 16k/单声道 PCM 喂入识别引擎，实现「说话 → 实时字幕」。
// 参考官方 Codelab：https://gitcode.com/HarmonyOS_Codelabs/speech-kit-codelab_-aicaption-ark-ts
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { audio } from '@kit.AudioKit';
import { promptAction } from '@kit.ArkUI';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { AICaptionComponent, AICaptionController, AICaptionOptions, AudioData } from '@kit.SpeechKit';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

const DOMAIN: number = 0x0001;
const TAG: string = 'AICaptionDemo';
// 与识别引擎安全块大小一致（640 字节 = 20ms @16k16bit 单声道）
const CHUNK: number = 640;

@Entry
@Component
export struct AICaptionDemoView {
  @Consume pageStack: NavPathStack;

  @State isShown: boolean = false;        // 字幕组件是否显示
  @State recognizing: boolean = false;    // 麦克风采集是否进行中
  @State captionError: string = '';       // 字幕错误提示
  @State statusTip: string = '点击下方按钮，对麦克风说话即可看到实时字幕';

  private controller: AICaptionController = new AICaptionController();
  private captionOption?: AICaptionOptions;
  private audioCapturer?: audio.AudioCapturer;
  private permOk: boolean = false;

  aboutToAppear(): void {
    this.captionOption = {
      initialOpacity: 1,
      onPrepared: (): void => {
        hilog.info(DOMAIN, TAG, 'AICaption onPrepared');
      },
      onError: (error: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'AICaption onError: %{public}d %{public}s', error.code, error.message);
        this.captionError = '字幕服务异常：' + error.message +
          '（本机可能缺少语音识别运行时，请在支持 SpeechKit 的设备上体验）';
        this.recognizing = false;
        this.isShown = false;
        this.statusTip = '字幕服务不可用';
      }
    };
  }

  aboutToDisappear(): void {
    this.releaseAll();
  }

  private releaseAll(): void {
    if (this.audioCapturer) {
      try {
        this.audioCapturer.stop();
        this.audioCapturer.release();
      } catch (e) { /* ignore */ }
      this.audioCapturer = undefined;
    }
    // AICaptionController 无 release/destroy 方法，组件销毁时由 AICaptionComponent 自行清理
  }

  private async getTokenId(): Promise<number> {
    try {
      const bundleInfo: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      return bundleInfo.appInfo.accessTokenId;
    } catch (e) {
      return 0;
    }
  }

  private async requestMicPermission(): Promise<void> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const result = await atManager.requestPermissionsFromUser(ctx, ['ohos.permission.MICROPHONE']);
    this.permOk = (result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    if (!this.permOk) {
      promptAction.showToast({ message: '麦克风权限未授权，无法使用字幕', duration: 1500 });
    }
  }

  // 检查/申请麦克风权限；返回是否授权
  private async ensurePermission(): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = await this.getTokenId();
      const status: abilityAccessCtrl.GrantStatus =
        await atManager.checkAccessToken(tokenId, 'ohos.permission.MICROPHONE');
      this.permOk = (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    } catch (e) {
      this.permOk = false;
    }
    if (!this.permOk) {
      await this.requestMicPermission();
    }
    return this.permOk;
  }

  // 把一帧 PCM 喂给字幕控制器（按 640 字节小块写入）
  private feedAudio(frame: ArrayBuffer): void {
    if (!this.isShown || !frame || frame.byteLength === 0) return;
    try {
      const bytes: Uint8Array = new Uint8Array(frame);
      for (let off: number = 0; off < bytes.byteLength; off += CHUNK) {
        const end: number = Math.min(off + CHUNK, bytes.byteLength);
        const audioData: AudioData = { data: bytes.slice(off, end) };
        this.controller.writeAudio(audioData);
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'writeAudio fail: %{public}s', err.message);
    }
  }

  private async startCaption(): Promise<void> {
    if (this.recognizing) return;
    const ok: boolean = await this.ensurePermission();
    if (!ok) return;
    try {
      const capturer = await audio.createAudioCapturer({
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        },
        capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 },
      });
      this.audioCapturer = capturer;
      // 框架缓冲区会被复用：先拷贝再处理，避免回调耗时期间被覆盖导致串帧
      capturer.on('readData', (buffer: ArrayBuffer): void => {
        const copied: ArrayBuffer = buffer.slice(0);
        this.feedAudio(copied);
      });
      this.isShown = true;
      this.captionError = '';
      this.statusTip = '正在聆听…请对麦克风说话';
      this.recognizing = true;
      await capturer.start();
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'startCaption fail: %{public}s', err.message);
      promptAction.showToast({ message: '启动字幕失败：' + err.message, duration: 2000 });
      this.recognizing = false;
      this.isShown = false;
    }
  }

  private async stopCaption(): Promise<void> {
    try {
      if (this.audioCapturer) {
        await this.audioCapturer.stop();
        await this.audioCapturer.release();
        this.audioCapturer = undefined;
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'stopCaption fail: %{public}s', err.message);
    }
    this.isShown = false;
    this.recognizing = false;
    this.statusTip = '已停止，点击下方按钮可重新开始';
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 顶部：返回 + 标题
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary'), $r('app.color.text_primary'), $r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.surface_variant'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.pageStack.pop();
        })
        Text('AI 实时字幕')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('92%')
      .margin({ top: SPACE.md, bottom: SPACE.md })

      Scroll() {
        Column() {
          // 功能说明卡
          Row() {
            Text('💬')
              .fontSize(22)
              .margin({ right: SPACE.md })
            Column() {
              Text('实时语音识别')
                .fontSize(FONT.body)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text('基于系统 SpeechKit 实时字幕能力，对麦克风说话即可同步显示文字')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: SPACE.xs })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(SPACE.lg)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.md)
          .margin({ bottom: SPACE.sm })
          .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })

          // 状态提示
          Text(this.statusTip)
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: SPACE.sm })

          // 字幕区域：进行中显示组件，否则显示占位
          if (this.isShown) {
            AICaptionComponent({
              isShown: this.isShown,
              controller: this.controller,
              options: this.captionOption
            })
              .width('100%')
              .height(220)
              .borderRadius(RADIUS.md)
              .margin({ bottom: SPACE.sm })
          } else {
            Column() {
              Text('💬')
                .fontSize(48)
                .margin({ bottom: SPACE.sm })
              Text('字幕区域（点击开始后显示）')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .height(220)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(RADIUS.md)
            .margin({ bottom: SPACE.sm })
          }

          // 错误提示
          if (this.captionError) {
            Text(this.captionError)
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.danger'))
              .width('100%')
              .padding(SPACE.md)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(RADIUS.sm)
              .margin({ bottom: SPACE.sm })
          }

          // 操作按钮
          Button(this.recognizing ? '停止识别' : '开始识别')
            .width('100%')
            .height(48)
            .fontSize(FONT.body)
            .fontColor($r('app.color.on_primary'))
            .backgroundColor(this.recognizing ? $r('app.color.danger') : $r('app.color.brand'))
            .borderRadius(RADIUS.lg)
            .onClick(() => {
              if (this.recognizing) {
                this.stopCaption();
              } else {
                this.startCaption();
              }
            })
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

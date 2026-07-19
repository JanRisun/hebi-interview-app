// 开口自测录音条：复用组件，按题目 id 存录音文件
// 能力：麦克风权限检查/动态申请 + AVRecorder 录制(m4a) + AVPlayer 回放 + 计时
// 仅用本机沙箱文件，不上传。API 参考 HarmonyOS MediaKit / Core File Kit / abilityAccessCtrl
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { FONT, RADIUS, SPACE } from '../utils/Theme';
import { AsrHelper } from '../utils/AsrHelper';

const DOMAIN: number = 0x0001;
const TAG: string = 'RecorderBar';

@Component
export struct RecorderBar {
  @Prop @Watch('onQidChange') qid: string = '';   // 题目 id，录音文件按此命名
  @State permOk: boolean = false;     // 麦克风权限是否授权
  @State recording: boolean = false;   // 是否正在录音
  @State playing: boolean = false;     // 是否正在回放
  @State sec: number = 0;            // 计时（秒）
  @State hasFile: boolean = false;    // 该题目是否已有历史录音
  @State transcribing: boolean = false;   // 是否正在本地转写
  @State hasTranscript: boolean = false; // 该题目是否已有转写文本
  @State transcriptText: string = '';    // 转写结果（端侧语音识别）

  private avRecorder: media.AVRecorder | undefined = undefined;
  private avPlayer: media.AVPlayer | undefined = undefined;
  private recFile: fileIo.File | undefined = undefined;
  private playFile: fileIo.File | undefined = undefined;
  private timer: number = 0;

  // 录音文件路径：应用沙箱 filesDir/rec_<qid>.wav（PCM/WAV，供 ASR 文件转写直接食用）
  private filePath(): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    return ctx.filesDir + '/rec_' + this.qid + '.wav';
  }

  // 转写文本路径：与录音同名的 .txt
  private transcriptPath(): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    return ctx.filesDir + '/rec_' + this.qid + '.txt';
  }

  aboutToAppear(): void {
    this.checkPerm();
  }

  aboutToDisappear(): void {
    this.forceStop();
  }

  // 题目切换：复位录音/回放状态，刷新是否有历史录音
  private onQidChange(): void {
    this.forceStop();
    this.transcriptText = '';
    this.hasTranscript = false;
    this.loadTranscript();
  }

  // 读回该题目历史转写文本（本机 txt）
  private loadTranscript(): void {
    try {
      const txt: string = fileIo.readTextSync(this.transcriptPath());
      this.transcriptText = txt;
      this.hasTranscript = txt.length > 0;
    } catch (e) {
      this.transcriptText = '';
      this.hasTranscript = false;
    }
  }

  // 端侧转写：调 AsrHelper 把录音文件转成文字，存本机并展示
  private async doTranscribe(): Promise<void> {
    if (this.transcribing) return;
    this.transcribing = true;
    try {
      const text: string = await AsrHelper.transcribeFile(this.filePath());
      this.transcriptText = text;
      this.hasTranscript = text.length > 0;
      if (text.length > 0) {
        try {
          const fd = fileIo.openSync(
            this.transcriptPath(),
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
          );
          fileIo.writeSync(fd.fd, text);
          fileIo.closeSync(fd.fd);
        } catch (e) { /* ignore */ }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'transcribe fail: %{public}s', err.message);
    } finally {
      this.transcribing = false;
    }
  }

  // 检查麦克风权限（失败不致命，默认显示授权按钮）
  private async checkPerm(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const tokenId: number = bundleInfo.appInfo.accessTokenId;
      const status = await atManager.checkAccessToken(tokenId, 'ohos.permission.MICROPHONE');
      this.permOk = (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      if (this.permOk) {
        this.hasFile = this.fileExists();
        this.loadTranscript();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'checkPerm fail: %{public}s', JSON.stringify(e));
      this.permOk = false;
    }
  }

  // 动态申请麦克风权限（运行时弹窗）
  private async requestPerm(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(
        getContext(this) as common.UIAbilityContext,
        ['ohos.permission.MICROPHONE']
      );
      this.permOk = (result.authResults[0] === 0);
      if (this.permOk) {
        this.hasFile = this.fileExists();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestPerm fail: %{public}s', JSON.stringify(e));
    }
  }

  private fileExists(): boolean {
    try {
      fileIo.accessSync(this.filePath());
      return true;
    } catch (e) {
      return false;
    }
  }

  private startTimer(): void {
    this.clearTimer();
    this.timer = setInterval((): void => { this.sec++; }, 1000);
  }

  private clearTimer(): void {
    if (this.timer !== 0) {
      clearInterval(this.timer);
      this.timer = 0;
    }
  }

  // 开始录音：prepare → start（严格状态机）
  private async startRec(): Promise<void> {
    if (!this.permOk) {
      await this.requestPerm();
      if (!this.permOk) return;
    }
    try {
      this.avRecorder = await media.createAVRecorder();
      this.avRecorder.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'rec error: %{public}s', err.message);
      });
      // 录音格式改 PCM/WAV：ASR 文件转写要求 16k/单声道/16bit 裸 PCM（WAV 封装，去 44 字节头即可喂）
      const avProfile: media.AVRecorderProfile = {
        audioBitrate: 256000,           // 16bit * 16000 * 1 = 256000 bps
        audioChannels: 1,
        audioCodec: media.CodecMimeType.AUDIO_PCM,
        audioSampleRate: 16000,
        fileFormat: media.ContainerFormatType.CFT_WAV,
      };
      const file = fileIo.openSync(
        this.filePath(),
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      this.recFile = file;
      const avConfig: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: avProfile,
        url: 'fd://' + file.fd.toString(),
      };
      await this.avRecorder.prepare(avConfig);
      await this.avRecorder.start();
      this.recording = true;
      this.sec = 0;
      this.startTimer();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'startRec fail: %{public}s', err.message);
    }
  }

  // 停止录音：stop → release，并关闭 fd
  private async stopRec(): Promise<void> {
    this.clearTimer();
    try {
      if (this.avRecorder) {
        await this.avRecorder.stop();
        await this.avRecorder.release();
        this.avRecorder = undefined;
      }
      if (this.recFile) {
        try { fileIo.closeSync(this.recFile.fd); } catch (e) { /* ignore */ }
        this.recFile = undefined;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'stopRec fail: %{public}s', err.message);
    }
    this.recording = false;
    this.hasFile = this.fileExists();
  }

  // 回放：创建 AVPlayer → 设置 fd 源 → play
  private async play(): Promise<void> {
    if (this.playing) {
      this.stopPlay();
      return;
    }
    try {
      this.avPlayer = await media.createAVPlayer();
      this.avPlayer.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'play error: %{public}s', err.message);
      });
      this.avPlayer.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        if (state === 'completed') {
          this.playing = false;
          this.clearTimer();
          this.sec = 0;
        }
      });
      const file = fileIo.openSync(this.filePath(), fileIo.OpenMode.READ_ONLY);
      this.playFile = file;
      this.avPlayer.url = 'fd://' + file.fd.toString();
      this.avPlayer.play();
      this.playing = true;
      this.sec = 0;
      this.startTimer();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'play fail: %{public}s', err.message);
    }
  }

  private stopPlay(): void {
    this.clearTimer();
    try {
      if (this.avPlayer) {
        this.avPlayer.stop();
        this.avPlayer.release();
        this.avPlayer = undefined;
      }
      if (this.playFile) {
        try { fileIo.closeSync(this.playFile.fd); } catch (e) { /* ignore */ }
        this.playFile = undefined;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'stopPlay fail: %{public}s', err.message);
    }
    this.playing = false;
    this.sec = 0;
  }

  // 强制复位（切题 / 离开页面）：释放资源、关闭 fd、复位状态
  private forceStop(): void {
    this.clearTimer();
    this.recording = false;
    this.playing = false;
    this.sec = 0;
    if (this.avRecorder) {
      this.avRecorder.release().then((): void => {}).catch((): void => {});
      this.avRecorder = undefined;
    }
    if (this.avPlayer) {
      this.avPlayer.release().then((): void => {}).catch((): void => {});
      this.avPlayer = undefined;
    }
    if (this.recFile) {
      try { fileIo.closeSync(this.recFile.fd); } catch (e) { /* ignore */ }
      this.recFile = undefined;
    }
    if (this.playFile) {
      try { fileIo.closeSync(this.playFile.fd); } catch (e) { /* ignore */ }
      this.playFile = undefined;
    }
    if (this.permOk) {
      this.hasFile = this.fileExists();
    }
  }

  private fmt(s: number): string {
    const m: number = Math.floor(s / 60);
    const ss: number = s % 60;
    return m + ':' + (ss < 10 ? '0' + ss : '' + ss);
  }

  build() {
    Column() {
      Text('开口自测')
        .fontSize(FONT.body)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: SPACE.xs })

      if (!this.permOk) {
        Button('授权麦克风，开始开口练习')
          .width('100%')
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .borderRadius(RADIUS.pill)
          .onClick(() => this.requestPerm())
      } else {
        Row({ space: 10 }) {
          Button(this.recording ? '停止录音' : '开始录音')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor(this.recording ? $r('app.color.danger') : $r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .onClick(() => {
              if (this.recording) this.stopRec();
              else this.startRec();
            })
          if (this.hasFile) {
            Button(this.playing ? '停止回放' : '回放')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor(this.playing ? $r('app.color.warning') : $r('app.color.surface_variant'))
              .fontColor(this.playing ? $r('app.color.on_primary') : $r('app.color.text_primary'))
              .borderRadius(RADIUS.pill)
              .onClick(() => this.play())
            // 本地语音识别转写（端侧、零密钥、隐私不出本机）
            Button(this.transcribing ? '转写中…' : '转写为文字')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor($r('app.color.brand'))
              .fontColor($r('app.color.on_primary'))
              .borderRadius(RADIUS.pill)
              .enabled(!this.transcribing)
              .onClick(() => this.doTranscribe())
          }
        }
        .width('100%')
        .margin({ top: SPACE.xs })

        Text(
          (this.recording ? '录音中 ' : (this.playing ? '回放中 ' : (this.hasFile ? '上次录音 ' : ''))) + this.fmt(this.sec)
        )
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ top: SPACE.xs })
        if (this.hasTranscript) {
          Text('我的口述转写（本地语音识别，对照逐字稿找差距）')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.brand'))
            .alignSelf(ItemAlign.Start)
            .margin({ top: SPACE.xs })
          Text(this.transcriptText)
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_body'))
            .lineHeight(22)
            .alignSelf(ItemAlign.Start)
            .margin({ top: SPACE.xs })
        }
        if (!this.hasFile && !this.recording && !this.playing) {
          Text('点「开始录音」口述作答，复盘时可回放对照参考答案')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_tertiary'))
            .alignSelf(ItemAlign.Start)
            .margin({ top: SPACE.xs })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: SPACE.md })
  }
}

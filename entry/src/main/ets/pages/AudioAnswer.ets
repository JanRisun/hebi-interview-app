// 音频作答页：单题作答模式，思考计时 + 音频录制
// 布局参考：顶部返回 + 标题，「查看题目」可折叠卡片，下方思考时间胶囊 + 重新计时，
// 中部大号 计时显示 + 圆形红色录制按钮 + 「开始录制」标签。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AnswerRecord, Question } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';

const DOMAIN: number = 0x0001;
const TAG: string = 'AudioAnswer';

// 默认作答时长上限（秒）：仅用于显示，不强制
const DEFAULT_SPEAK_SEC: number = 300;
// 答题点评页跳转参数（规避 arkts-no-untyped-obj-literals）
interface AudioReviewParam { id: string }

@Component
export struct AudioAnswerView {
  @State question: Question | null = null;
  @State showQuestion: boolean = true;        // 「查看题目」折叠态
  @State thinkElapsed: number = 0;            // 思考已用秒（正计时，累计增加）
  @State thinkActive: boolean = false;        // 思考计时是否在跑
  @State thinkSavedSec: number = 0;           // 开始录制时固定的思考时长
  @State recorded: boolean = false;           // 是否真正录过音（用于落盘判断）
  @State recSec: number = 0;                  // 录制已用秒
  @State recording: boolean = false;          // 是否正在录音
  @State amplitudes: number[] = [];           // 最近若干帧音频峰值振幅（0~1），用于波形可视化
  @State recordFinished: boolean = false;     // 录制是否完成（完成显示回放 + 操作按钮）
  @State isPlaying: boolean = false;          // 是否正在回放
  @State playbackCompleted: boolean = false;  // 是否已播完（用于显示重新播放图标）
  @State playbackProgress: number = 0;         // 回放进度（毫秒）
  @State playbackDuration: number = 0;        // 回放总时长（毫秒）
  @State permOk: boolean = false;             // 麦克风权限
  @State permChecked: boolean = false;        // 是否完成过权限检查
  @Prop params: Object;                       // 路由参数：{ id, kw? }

  // 录音相关
  private audioCapturer: audio.AudioCapturer | undefined = undefined;
  private recFile: fileIo.File | undefined = undefined;
  private pcmOffset: number = 0;
  private recPath: string = '';

  // 回放相关：使用 AVPlayer 直接播放 WAV 文件（原生解码，干净无噪）
  private avPlayer: media.AVPlayer | undefined = undefined;
  private avState: string = '';
  private playFile: fileIo.File | undefined = undefined; // 回放打开的文件句柄（fdSrc 需持有一个打开的 fd）
  private pendingPlay: boolean = false;                  // 尚未 prepared 时用户点播放，挂起待 prepared 后自动播放

  // 计时器句柄
  private thinkTimer: number = 0;
  private recTimer: number = 0;

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  @Consume pageStack: NavPathStack;

  aboutToAppear(): void {
    const p = (this.params ?? {}) as Record<string, Object>;
    const id: string = (p['id'] as string) ?? '';
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d) => {
      const q: Question | null = DataStore.questionById(id) ?? null;
      this.question = q;
      // 进入页面即启动思考计时（正计时，累计增加）
      this.startThinkTimer();
      // 预检麦克风权限
      this.checkMicPermission();
    });
  }

  aboutToDisappear(): void {
    this.stopThinkTimer();
    this.stopRecTimer();
    this.stopRecording();  // 离开页面 fire-and-forget，系统会回收
    this.releasePlayback();
  }

  // 取建议作答时长（用于显示上限）
  private speakLimit(): number {
    const q: Question | null = this.question;
    if (q && q.speakTime && q.speakTime > 0) return q.speakTime;
    return DEFAULT_SPEAK_SEC;
  }

  // 思考计时（累计增加，正计时）
  private startThinkTimer(): void {
    if (this.thinkActive) return;
    this.thinkActive = true;
    const tick = (): void => {
      if (!this.thinkActive) return;
      this.thinkElapsed += 1;
      this.thinkTimer = setTimeout(tick, 1000);
    };
    this.thinkTimer = setTimeout(tick, 1000);
  }

  private stopThinkTimer(): void {
    this.thinkActive = false;
    if (this.thinkTimer !== 0) {
      clearTimeout(this.thinkTimer);
      this.thinkTimer = 0;
    }
  }

  // 重新计时思考时间
  private resetThinkTimer(): void {
    this.stopThinkTimer();
    this.thinkElapsed = 0;
    this.startThinkTimer();
  }

  // 录制正计时
  private startRecTimer(): void {
    if (this.recTimer !== 0) return;
    const tick = (): void => {
      this.recSec += 1;
      this.recTimer = setTimeout(tick, 1000);
    };
    this.recTimer = setTimeout(tick, 1000);
  }

  private stopRecTimer(): void {
    if (this.recTimer !== 0) {
      clearTimeout(this.recTimer);
      this.recTimer = 0;
    }
  }

  // 麦克风权限检查
  private async checkMicPermission(): Promise<void> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = await this.getTokenId();
      const status: abilityAccessCtrl.GrantStatus = await atManager.checkAccessToken(tokenId, 'ohos.permission.MICROPHONE');
      this.permOk = (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    } catch (e) {
      this.permOk = false;
    }
    this.permChecked = true;
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
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(ctx, ['ohos.permission.MICROPHONE']);
      this.permOk = (result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      if (!this.permOk) {
        promptAction.showToast({ message: '麦克风权限未授权，无法录制', duration: 1500 });
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestMicPermission fail: %{public}s', err.message);
    }
  }

  // 切换录音
  private async toggleRecording(): Promise<void> {
    if (this.recording) {
      await this.stopRecording();
    } else {
      if (!this.permOk) {
        await this.requestMicPermission();
        if (!this.permOk) return;
      }
      this.startRecording();
    }
  }

  // 开始录音
  private async startRecording(): Promise<void> {
    try {
      // 点击开始录制：暂停思考计时，固定「思考了多久」
      this.stopThinkTimer();
      this.thinkSavedSec = this.thinkElapsed;
      this.recorded = true;
      this.amplitudes = [];
      const ctx = getContext(this) as common.UIAbilityContext;
      const fileName: string = 'audio_answer_' + (this.question ? this.question.id : 'unknown') + '_' + Date.now() + '.wav';
      this.recPath = ctx.filesDir + '/' + fileName;
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
      const file = fileIo.openSync(
        this.recPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      this.recFile = file;
      this.writeWavHeader(file.fd, 0);
      this.pcmOffset = 44;
      capturer.on('readData', (buffer: ArrayBuffer): void => {
        // 框架缓冲区会被复用：先拷贝再写入/处理，否则回调耗时期间 buffer 被覆盖会导致 PCM 串帧（炸麦/杂音）
        const copied: ArrayBuffer = buffer.slice(0);
        if (this.recFile) {
          try {
            const n: number = fileIo.writeSync(this.recFile.fd, copied);
            this.pcmOffset += n;
          } catch (err) {
            const e2 = err as BusinessError;
            hilog.error(DOMAIN, TAG, 'writeAudio fail: %{public}s', e2.message);
          }
        }
        // 计算本帧 PCM 峰值（16bit 有符号），归一化到 0~1，用于波形可视化（基于拷贝，不触碰框架缓冲区）
        try {
          const dv: DataView = new DataView(copied);
          let peak: number = 0;
          for (let i: number = 0; i + 1 < dv.byteLength; i += 2) {
            const v: number = Math.abs(dv.getInt16(i, true));
            if (v > peak) peak = v;
          }
          const amp: number = peak > 0 ? Math.min(1, peak / 32768) : 0;
          const next: number[] = this.amplitudes.concat([amp]);
          if (next.length > 40) next.splice(0, next.length - 40);
          this.amplitudes = next;
        } catch (e) { /* ignore */ }
      });
      await capturer.start();
      this.recording = true;
      this.recSec = 0;
      this.startRecTimer();
    } catch (e) {
      const err = e as BusinessError;
      this.recorded = false;
      hilog.error(DOMAIN, TAG, 'startRecording fail: %{public}s', err.message);
      promptAction.showToast({ message: '开始录音失败：' + err.message, duration: 2000 });
    }
  }

  // 停止录音：回写 WAV 头 + 释放 capturer，并保存答题记录
  private async stopRecording(): Promise<void> {
    this.stopRecTimer();
    // 先等 capturer 彻底停止，确保所有音频帧已落盘，再关文件写头
    try {
      if (this.audioCapturer) {
        try {
          await this.audioCapturer.stop();
          await this.audioCapturer.release();
        } catch (e) {
          const ae = e as BusinessError;
          hilog.error(DOMAIN, TAG, 'stop capturer fail: %{public}s', ae.message);
        }
        this.audioCapturer = undefined;
      }
    } catch (e) {
      /* ignore outer */
    }
    try {
      if (this.recFile) {
        const dataSize: number = Math.max(0, this.pcmOffset - 44);
        try {
          fileIo.lseek(this.recFile.fd, 0, 0);
          this.writeWavHeader(this.recFile.fd, dataSize);
        } catch (e) { /* ignore */ }
        try {
          fileIo.closeSync(this.recFile.fd);
        } catch (e) { /* ignore */ }
        this.recFile = undefined;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'stopRecording close fail: %{public}s', err.message);
    }
    this.recording = false;
    if (this.recorded) {
      const dataSize2: number = Math.max(0, this.pcmOffset - 44);
      const byteRate: number = 16000 * 1 * 16 / 8;
      this.playbackDuration = Math.floor(dataSize2 / byteRate * 1000);
      this.saveAnswerRecord();
      this.recordFinished = true;
      this.initPlayback(this.recPath);
    }
  }

  // ---- 回放：使用 AVPlayer 直接播放 WAV（原生解码，干净无噪） ----

  // 初始化：打开 WAV 文件并设置 fd 源，按状态机准备（参照详情页 RecorderBar 的可工作实现）
  private async initPlayback(path: string): Promise<void> {
    this.releasePlayback();
    try {
      const stat: fileIo.Stat = fileIo.statSync(path);
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      this.playFile = file;
      const player: media.AVPlayer = await media.createAVPlayer();
      this.avPlayer = player;

      player.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'avPlayer error: %{public}s', err.message);
      });

      player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        this.avState = state;
        if (state === 'initialized') {
          // fd 源设置后进入 initialized，需主动 prepare 才能进入 prepared
          try { player.prepare(); } catch (e) { /* ignore */ }
        } else if (state === 'prepared') {
          this.playbackDuration = player.duration;
          this.playbackCompleted = false;
          // 若用户在 prepared 之前就点了播放，这里兜底自动开播
          if (this.pendingPlay) {
            this.pendingPlay = false;
            try { player.play(); } catch (e) { /* ignore */ }
            this.isPlaying = true;
          }
        } else if (state === 'completed') {
          this.isPlaying = false;
          this.playbackCompleted = true;
          this.playbackProgress = this.playbackDuration;
        } else if (state === 'released') {
          this.avPlayer = undefined;
        }
      });

      // 播放进度（毫秒）由系统回调驱动，无需手动画定时器
      player.on('timeUpdate', (time: number): void => {
        this.playbackProgress = time;
      });

      // 设置 fd 源（带 offset/length），比 player.url='file://...' 更稳，避免读到错误区间导致无声
      player.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'initPlayback fail: %{public}s', err.message);
    }
  }

  private releasePlayback(): void {
    this.isPlaying = false;
    this.pendingPlay = false;
    this.avState = '';
    if (this.avPlayer) {
      try {
        this.avPlayer.stop();
        this.avPlayer.release();
      } catch (e) { /* ignore */ }
      this.avPlayer = undefined;
    }
    if (this.playFile) {
      try { fileIo.closeSync(this.playFile.fd); } catch (e) { /* ignore */ }
      this.playFile = undefined;
    }
  }

  // 播放 / 暂停 / 回放切换
  private togglePlayback(): void {
    try {
      const p = this.avPlayer;
      if (!p) return;
      if (this.isPlaying) {
        p.pause();
        this.isPlaying = false;
        return;
      }
      if (this.playbackCompleted) {
        p.seek(0);
        this.playbackProgress = 0;
        this.playbackCompleted = false;
      }
      // 若状态机尚未 prepared（异步准备未完成），挂起，待 prepared 后自动开播
      if (this.avState !== 'prepared' && this.avState !== 'playing' && this.avState !== 'paused') {
        this.pendingPlay = true;
        return;
      }
      try { p.play(); } catch (e) { /* ignore */ }
      this.isPlaying = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'togglePlayback fail: %{public}s', err.message);
    }
  }

  // 拖拽进度跳转（毫秒）
  private seekTo(ms: number): void {
    try {
      const p = this.avPlayer;
      if (!p) return;
      p.seek(ms);
      this.playbackProgress = ms;
      if (this.playbackCompleted) {
        this.playbackCompleted = false;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'seekTo fail: %{public}s', err.message);
    }
  }

  // 重录：释放 AVPlayer，重置回放 / 录制状态，删除旧文件
  private async rerecord(): Promise<void> {
    this.releasePlayback();
    try {
      if (this.recPath) {
        try { fileIo.unlinkSync(this.recPath); } catch (e) { /* ignore */ }
      }
    } catch (e) { /* ignore */ }
    this.recordFinished = false;
    this.isPlaying = false;
    this.playbackCompleted = false;
    this.playbackProgress = 0;
    this.playbackDuration = 0;
    this.amplitudes = [];
    this.recSec = 0;
    this.recorded = false;
    this.recPath = '';
  }

  // 提交点评：跳转到答题点评页（AI 分析结果页面），传入题目 id 用于回显题目内容
  private submitReview(): void {
    const id: string = this.question ? this.question.id : '';
    const params: AudioReviewParam = { id: id };
    this.pageStack.pushPathByName('AudioReview', params);
  }

  // 保存答题记录（思考时长 + 作答时长）到本地偏好存储
  private async saveAnswerRecord(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const prefs = await preferences.getPreferences(ctx, 'practice');
      const id: string = this.question ? this.question.id : 'unknown';
      const title: string = this.question ? this.question.title : '';
      const rec: AnswerRecord = {
        id: id,
        title: title,
        thinkSec: this.thinkSavedSec,
        speakSec: this.recSec,
        date: this.nowStr(),
        audioPath: this.recPath
      };
      prefs.putSync('a_' + id, JSON.stringify(rec));
      const raw: string = prefs.getSync('a_ids', '') as string;
      const ids: string[] = raw ? raw.split(',') : [];
      if (ids.indexOf(id) < 0) {
        ids.push(id);
        prefs.putSync('a_ids', ids.join(','));
      }
      await prefs.flush();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'saveAnswerRecord fail: %{public}s', err.message);
    }
  }

  private nowStr(): string {
    const d: Date = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n : '' + n);
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  // 写标准 WAV 头（PCM 16k/单/16bit）
  private writeWavHeader(fd: number, dataSize: number): void {
    const buf: ArrayBuffer = new ArrayBuffer(44);
    const dv: DataView = new DataView(buf);
    const sRate: number = 16000;
    const ch: number = 1;
    const bits: number = 16;
    const byteRate: number = sRate * ch * bits / 8;
    const blockAlign: number = ch * bits / 8;
    this.setStr(dv, 0, 'RIFF');
    dv.setUint32(4, 36 + dataSize, true);
    this.setStr(dv, 8, 'WAVE');
    this.setStr(dv, 12, 'fmt ');
    dv.setUint32(16, 16, true);
    dv.setUint16(20, 1, true);
    dv.setUint16(22, ch, true);
    dv.setUint32(24, sRate, true);
    dv.setUint32(28, byteRate, true);
    dv.setUint16(32, blockAlign, true);
    dv.setUint16(34, bits, true);
    this.setStr(dv, 36, 'data');
    dv.setUint32(40, dataSize, true);
    fileIo.writeSync(fd, buf, { offset: 0, length: 44 });
  }

  private setStr(dv: DataView, off: number, s: string): void {
    for (let i: number = 0; i < s.length; i++) {
      dv.setUint8(off + i, s.charCodeAt(i));
    }
  }

  private fmt(s: number): string {
    const m: number = Math.floor(s / 60);
    const ss: number = s % 60;
    return m + ':' + (ss < 10 ? '0' + ss : '' + ss);
  }

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
        Text('音频作答')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .margin({ left: SPACE.md })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.xs, bottom: SPACE.sm })

      // 「查看题目」可折叠卡片
      Column() {
        Row() {
          Row() {
            Text('💬')
              .fontSize(14)
              .margin({ right: SPACE.sm })
            Text('查看题目')
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title'))
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          SymbolGlyph(this.showQuestion ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showQuestion = !this.showQuestion;
        })

        if (this.showQuestion && this.question) {
          Column() {
            Text(this.question.title)
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title'))
              .margin({ bottom: SPACE.sm })
              .alignSelf(ItemAlign.Start)
            Text(this.question.prompt)
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.text_body'))
              .lineHeight(22)
              .alignSelf(ItemAlign.Start)
          }
          .width('100%')
          .margin({ top: SPACE.md })
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('92%')
      .padding(SPACE.md)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.md)
      .margin({ top: SPACE.sm, bottom: SPACE.lg })
      .alignItems(HorizontalAlign.Start)

      // 录制完成态：显示回放控件 + AI 提示 + 重录 / 提交点评按钮
      if (this.recordFinished) {
        Column() {
          // 顶部留白，整体布局下移
          Blank().height(SPACE.lg)

          // 作答概览：思考时间 + 作答时长
          Row() {
            Column() {
              Text('思考时间')
                .fontSize(FONT.bodySm)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 2 })
              Text(this.fmt(this.thinkSavedSec))
                .fontSize(FONT.title)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_title'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            Column() {
              Text('作答时长')
                .fontSize(FONT.bodySm)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 2 })
              Text(this.fmt(this.recSec))
                .fontSize(FONT.title)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_title'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }
          .width('92%')
          .padding({ top: SPACE.md, bottom: SPACE.md })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.md)
          .margin({ bottom: SPACE.md })

          // 回放条：左播放按钮 + 中间时间/进度
          Row() {
            // 播放/暂停按钮
            Stack({ alignContent: Alignment.Center }) {
              if (this.isPlaying) {
                // 暂停图标：两根白色竖条
                Row() {
                  Column()
                    .width(4)
                    .height(16)
                    .backgroundColor($r('app.color.on_primary'))
                    .borderRadius(1)
                    .margin({ right: 4 })
                  Column()
                    .width(4)
                    .height(16)
                    .backgroundColor($r('app.color.on_primary'))
                    .borderRadius(1)
                }
              } else if (this.playbackCompleted) {
                // 播放完毕：重新播放（循环箭头）。用 scale 整体放大加粗线条，避免 bold 变体导致的偏差
                SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                  .fontSize(20)
                  .fontColor([$r('app.color.on_primary')])
                  .scale({ x: 1.3, y: 1.3 })
              } else {
                // 暂停中/初始：白色实心三角播放图标（扁平填充无立体感，与暂停竖条风格一致）
                SymbolGlyph($r('sys.symbol.play_fill'))
                  .fontSize(18)
                  .fontColor([$r('app.color.on_primary')])
                  .offset({ x: 1 })
              }
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor($r('app.color.brand'))
            .onClick(() => {
              this.togglePlayback();
            })

            // 中间：当前时间 + 进度 + 总时长
            Column() {
              Row() {
                Text(this.fmt(Math.floor(this.playbackProgress / 1000)))
                  .fontSize(FONT.bodySm)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ right: SPACE.sm })
                Blank()
                Text(this.fmt(Math.max(0, Math.floor(this.playbackDuration / 1000))))
                  .fontSize(FONT.bodySm)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .margin({ bottom: 4 })

              Slider({
                value: this.playbackProgress,
                min: 0,
                max: this.playbackDuration > 0 ? this.playbackDuration : 1,
                step: 100
              })
                .blockColor($r('app.color.brand'))
                .trackColor($r('app.color.brand_light'))
                .selectedColor($r('app.color.brand'))
                .trackThickness(3)
                .blockSize({ width: 10, height: 10 })
                .width('100%')
                .onChange((value: number): void => {
                  this.seekTo(value);
                })
            }
            .layoutWeight(1)
            .margin({ left: SPACE.md, right: SPACE.md })
          }
          .width('92%')
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.md, bottom: SPACE.md })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.md)
          .alignItems(VerticalAlign.Center)
          .margin({ top: SPACE.md })

          // AI 点评提示
          Row() {
            Text('ⓘ')
              .fontSize(14)
              .fontColor('#E0A458')
              .margin({ right: SPACE.sm })
            Text('AI点评是基于本地模型生成针对性点评')
              .fontSize(FONT.bodySm)
              .fontColor('#9A6E2F')
              .layoutWeight(1)
          }
          .width('92%')
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
          .backgroundColor('#FFF6E5')
          .borderRadius(RADIUS.sm)
          .margin({ top: SPACE.md })
          .alignItems(VerticalAlign.Center)

          Blank()

          // 底部按钮：重录 / 提交点评
          Row() {
            Button('重录')
              .layoutWeight(1)
              .height(48)
              .fontSize(FONT.body)
              .fontColor($r('app.color.on_primary'))
              .backgroundColor($r('app.color.btn_neutral_bg'))
              .borderRadius(RADIUS.md)
              .onClick(() => {
                this.rerecord();
              })

            Button('提交点评')
              .layoutWeight(1)
              .height(48)
              .fontSize(FONT.body)
              .fontColor($r('app.color.on_primary'))
              .backgroundColor('#FF3B30')
              .borderRadius(RADIUS.md)
              .margin({ left: SPACE.md })
              .onClick(() => {
                this.submitReview();
              })
          }
          .width('92%')
          .margin({ bottom: SPACE.md })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 思考时间行（未录制时）/ 实时波形（录制中）
        if (this.recording) {
          // 实时音频波形：按振幅高低渲染竖条，居中显示
          Row() {
            ForEach(this.amplitudes, (amp: number) => {
              Column()
                .width(3)
                .height(Math.max(4, Math.floor(amp * 40)))
                .backgroundColor($r('app.color.brand'))
                .borderRadius(1.5)
                .margin({ left: 2, right: 2 })
            })
          }
          .width('92%')
          .height(56)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        } else {
          // 思考时间行：左胶囊 + 右重新计时
          Row() {
            Row() {
              Text('🕐')
                .fontSize(13)
                .margin({ right: SPACE.xs })
              Text('思考时间 ' + this.fmt(this.thinkElapsed))
                .fontSize(FONT.body)
                .fontColor($r('app.color.brand'))
            }
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(RADIUS.pill)
            .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
            Blank()
            Row() {
              Text('↻')
                .fontSize(13)
                .fontColor($r('app.color.brand'))
                .margin({ right: 4 })
              Text('重新计时')
                .fontSize(FONT.body)
                .fontColor($r('app.color.brand'))
            }
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(RADIUS.pill)
            .onClick(() => {
              this.resetThinkTimer();
            })
          }
          .width('92%')
          .alignItems(VerticalAlign.Center)
        }

        // 录制区：上方计时 + 中部大圆形按钮 + 下方状态文案
        Column() {
          // 录制中：左红点 + 时间 / 总时长
          Row() {
            if (this.recording) {
              Column()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.danger'))
                .margin({ right: SPACE.sm })
            }
            Text(this.fmt(this.recSec) + ' / ' + this.fmt(this.speakLimit()))
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: SPACE.xl, bottom: SPACE.xl })

          // 大圆形按钮：未录制时为蓝色渐变 + 🎙；录制中切换为深蓝渐变 + 白色停止方块 + 微缩放
          Stack({ alignContent: Alignment.Center }) {
            // 阴影/光晕层（外圈虚化点）
            if (this.recording) {
              Column()
                .width(132)
                .height(132)
                .borderRadius(66)
                .backgroundColor('#332563EB')
                .opacity(0.6)
            }
            // 录制进度环：橙色描边，紧贴按钮，进度按时长上限展示
            if (this.recording) {
              Progress({
                value: this.recSec,
                total: this.speakLimit(),
                type: ProgressType.Ring
              })
              .width(118)
              .height(118)
              .style({ strokeWidth: 4 })
              .color($r('app.color.accent'))
              .backgroundColor('#00000000')
            }
            Column() {
              if (this.recording) {
                // 录制中：白色圆角方块（停止图标）
                Column()
                  .width(32)
                  .height(32)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.on_primary'))
              } else {
                Text('🎙')
                  .fontSize(48)
                  .fontColor($r('app.color.on_primary'))
              }
            }
            .width(112)
            .height(112)
            .borderRadius(56)
            .linearGradient({
              angle: 180,
              colors: [
                [$r('app.color.brand'), 0],
                [$r('app.color.brand_dark'), 1]
              ]
            })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .shadow({ radius: 18, color: '#40000000', offsetY: 6 })
            .scale({ x: this.recording ? 0.92 : 1, y: this.recording ? 0.92 : 1 })
            .animation({ duration: 200, curve: Curve.EaseOut })
            .onClick(() => {
              this.toggleRecording();
            })
          }
          .width(140)
          .height(140)

          Text(this.recording ? '正在录制，点击后完成录制' : '开始录制')
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: SPACE.md })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .linearGradient({
      angle: 180,
      colors: [
        [$r('app.color.brand_light'), 0],
        [$r('app.color.tag_bg'), 0.4],
        [$r('app.color.background'), 1]
      ]
    })
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 音频作答是整屏 NavDestination，进入后首页悬浮 Tab 栏已隐藏，底部只留系统安全区
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}
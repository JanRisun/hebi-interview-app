// 开口自测录音条：复用组件，按题目 id 存录音文件
// 能力：麦克风权限检查/动态申请 + OH Audio 直录 PCM(WAV) + AVPlayer 回放 + 计时
// 仅用本机沙箱文件，不上传。API 参考 HarmonyOS MediaKit / Core File Kit / abilityAccessCtrl
import { common, Want } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { promptAction } from '@kit.ArkUI';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { FONT, RADIUS, SPACE } from '../utils/Theme';
import { AsrHelper } from '../utils/AsrHelper';

const DOMAIN: number = 0x0001;
const TAG: string = 'RecorderBar';

@Component
export struct RecorderBar {
  @Prop @Watch('onQidChange') qid: string = '';   // 题目 id，录音文件按此命名
  @State permOk: boolean = false;     // 麦克风权限是否授权
  @State permDenied: boolean = false;  // 用户曾拒绝过（用于切换按钮文案 & 弹窗指引）
  @State recording: boolean = false;   // 是否正在录音
  @State playing: boolean = false;     // 是否正在回放
  @State paused: boolean = false;      // 是否暂停回放（可继续）
  @State sec: number = 0;            // 计时（秒）
  @State recDuration: number = 0;     // 本次录音时长（秒），回放时作为计时上界
  @State hasFile: boolean = false;    // 该题目是否已有历史录音
  @State transcribing: boolean = false;   // 是否正在本地转写
  @State hasTranscript: boolean = false; // 该题目是否已有转写文本
  @State transcriptText: string = '';    // 转写结果（端侧语音识别）

  // 实时语音转写（语音→文字）：录音时用 speechRecognizer 实时识别，文字写入 liveText。
  // Core Speech Kit 当前仅支持离线识别（online:1），需设备已下载「中文语音识别模型」。
  // 无模型时 createEngine 会返回错误，asrError 可见并指导用户去系统设置下载。
  private asrEngine?: speechRecognizer.SpeechRecognitionEngine;
  private asrSession: string = '';
  private asrListening: boolean = false; // startListening 成功后置 true（onStart 回调），之后才能 writeAudio
  private asrCommitted: string = '';     // 已确认整句（isFinal）累积
  private asrGuard: number = 0;          // 实时识别兜底定时器（防止异常时卡死）
  @State liveText: string = '';          // 实时识别文字（自己的窗口显示）
  @State asrError: string = '';          // 识别失败原因（可见，便于排查）
  @State captionShown: boolean = false;  // 是否展示实时转写窗口
  @State manualText: string = '';        // 手动编辑的文字稿（ASR 不可用时兜底）

  private audioCapturer: audio.AudioCapturer | undefined = undefined;  // OH Audio 直录 PCM
  private avPlayer: media.AVPlayer | undefined = undefined;
  private recFile: fileIo.File | undefined = undefined;
  private pcmOffset: number = 0;   // 已写入 PCM 字节数（WAV 头 44 字节之后）
  private playFile: fileIo.File | undefined = undefined;
  private tickTimer: number = 0;       // 递归 setTimeout 句柄
  private tickActive: boolean = false;   // 守护标志：stop 后置 false，防止回调再排下一跳

  // 录音文件路径：应用沙箱 filesDir/rec_<qid>.wav（OH Audio 直录 PCM 16k/单/16bit，对接 AsrHelper 的 WAV 头跳过逻辑）
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
    this.captionShown = false;   // 切题复位：隐藏上一题的字幕区
    this.liveText = '';
    this.asrError = '';
    this.asrCommitted = '';
    this.manualText = '';
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

  // 端侧转写：录音已是 WAV(PCM 16k/单/16bit)，直接调 AsrHelper 转成文字，存本机并展示。
  // 全程离线、零密钥、隐私不出本机。
  private async doTranscribe(): Promise<void> {
    if (this.transcribing) return;
    this.transcribing = true;
    try {
      const text: string = await AsrHelper.transcribeFile(this.filePath());
      if (text.length > 0) {
        this.transcriptText = text;
        this.hasTranscript = true;
        try {
          const fd = fileIo.openSync(
            this.transcriptPath(),
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
          );
          fileIo.writeSync(fd.fd, text);
          fileIo.closeSync(fd.fd);
        } catch (e) { /* ignore */ }
      } else {
        // 引擎跑通但无文字（静音/非中文/离线模型精度有限），给出占位提示而非空白
        this.transcriptText = '[未识别到文字，请确认录音有清晰人声]';
        this.hasTranscript = true;
      }
    } catch (e) {
      const msg: string = (e as BusinessError)?.message || (e as Error)?.message || '未知错误';
      hilog.error(DOMAIN, TAG, 'transcribe fail: %{public}s', msg);
      // 把失败原因也展示在转写区，避免"点了没反应"的错觉
      this.transcriptText = '转写失败：' + msg;
      this.hasTranscript = true;
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
      this.permDenied = !this.permOk;
      if (this.permOk) {
        this.hasFile = this.fileExists();
        this.loadTranscript();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'checkPerm fail: %{public}s', JSON.stringify(e));
      this.permOk = false;
    }
  }

  // 动态申请麦克风权限（运行时弹窗）；拒绝后弹自定义提示，引导用户去系统设置
  private async requestPerm(): Promise<void> {
    // 先同步静默检查（处理从系统设置手动授权后返回的场景）
    await this.checkPerm();
    if (this.permOk) return;

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(
        getContext(this) as common.UIAbilityContext,
        ['ohos.permission.MICROPHONE']
      );
      this.permOk = (result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      if (this.permOk) {
        this.permDenied = false;
        this.hasFile = this.fileExists();
      } else {
        this.permDenied = true;
        // 弹窗告知用户如何手动开启
        promptAction.showDialog({
          title: '麦克风权限未授权',
          message: '口头作答需要麦克风权限。您可重试并在系统弹窗中选择「允许」，或前往系统设置手动开启。',
          buttons: [
            { text: '重试', color: '#007DFF' },
            { text: '去设置', color: '#007DFF' },
          ],
        }).then((res) => {
          if (res.index === 0) {
            // 重试 → 再次拉起系统权限弹窗
            this.requestPerm();
          } else if (res.index === 1) {
            // 去设置 → 打开应用信息页，用户可手动改权限
            this.openAppSettings();
          }
        });
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestPerm fail: %{public}s', JSON.stringify(e));
    }
  }

  // 跳转系统设置 → 本应用详情（用户可手动开启麦克风权限）
  private openAppSettings(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
          // 传入当前应用 bundleName，设置页自动定位到本应用
          pushParams: ctx.abilityInfo.bundleName,
        },
      };
      ctx.startAbility(want);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'openAppSettings fail: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '无法跳转设置，请手动开启', duration: 2000 });
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

  // 写标准 WAV 头（44 字节，PCM 16k/单/16bit）。dataSize=数据区字节数；
  // 录音前写 0 占位，停止时回写真实值（PCM 数据连续写在 44 字节之后）。
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
    dv.setUint32(16, 16, true);          // subchunk1Size
    dv.setUint16(20, 1, true);            // PCM
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

  // 统一计时：带守护标志的递归 setTimeout（比 setInterval 更稳，stop 后绝不再排下一跳，杜绝"清不掉/叠加"）
  private startTick(kind: 'rec' | 'play'): void {
    this.stopTick();
    this.tickActive = true;
    const loop = (): void => {
      if (!this.tickActive) return;
      this.sec++;
      if (kind === 'play') {
        const limit: number = this.recDuration > 0 ? this.recDuration : 600;  // 有界：录音多久回放就多久，兜底 10 分钟
        if (this.sec >= limit) {
          this.stopPlay();
          return;
        }
      }
      this.tickTimer = setTimeout(loop, 1000);
    };
    this.tickTimer = setTimeout(loop, 1000);
  }

  private stopTick(): void {
    this.tickActive = false;
    if (this.tickTimer !== 0) {
      clearTimeout(this.tickTimer);
      this.tickTimer = 0;
    }
  }

  // 开始录音：OH Audio AudioCapturer 直录 PCM 16k/单/16bit → 写 WAV（44 头 + PCM），对接 AsrHelper
  private async startRec(): Promise<void> {
    if (!this.permOk) {
      await this.requestPerm();
      if (!this.permOk) return;
    }
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
      const file = fileIo.openSync(
        this.filePath(),
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      this.recFile = file;
      this.writeWavHeader(file.fd, 0);   // 占位头（dataSize=0），停止时回写真实值
      this.pcmOffset = 44;
      let firstChunk: boolean = true;
      capturer.on('readData', (buffer: ArrayBuffer): void => {
        if (this.recFile) {
          try {
            // 写整个 buffer，文件光标自动前移（writeSync 的 offset 在 ArrayBuffer 模式下是"源缓冲区内偏移"，不能当文件位置用）
            const n: number = fileIo.writeSync(this.recFile.fd, buffer);
            this.pcmOffset += n;   // 仅累计真实写入字节数，用于回写 WAV 头 dataSize
            if (firstChunk) {
              firstChunk = false;
              hilog.info(DOMAIN, TAG, 'readData 首包 buffer=%{public}d 字节', buffer.byteLength);
            }
          } catch (err) {
            const e2 = err as BusinessError;
            hilog.error(DOMAIN, TAG, 'readData 写文件失败: %{public}s', e2.message);
          }
        }
        // 实时语音转写：同一块 PCM 喂给 speechRecognizer，识别文字写入 liveText（自己的窗口显示）
        if (this.asrEngine && this.asrSession) {
          this.feedAsr(buffer);
        }
      });
      await capturer.start();
      hilog.info(DOMAIN, TAG, 'capturer.start 成功，开始采集麦克风');
      this.recording = true;
      this.sec = 0;
      this.liveText = '';
      this.asrError = '';
      this.asrCommitted = '';
      this.captionShown = true;   // 展示实时转写窗口（说话即出文字）
      this.startTick('rec');
      this.startRealtimeAsr();    // 启动实时语音识别（文字写入 liveText）
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'startRec fail: %{public}s', err.message);
    }
  }

  // 停止录音：stop → release，回写真实 WAV 头（dataSize），关闭 fd
  private async stopRec(): Promise<void> {
    this.stopTick();
    try {
      if (this.audioCapturer) {
        try { await this.audioCapturer.stop(); } catch (e) { /* ignore */ }
        try { await this.audioCapturer.release(); } catch (e) { /* ignore */ }
        this.audioCapturer = undefined;
      }
      if (this.recFile) {
        const dataSize: number = Math.max(0, this.pcmOffset - 44);
        try {
          // 回到文件头再回写 WAV 头：writeSync 写在当前光标处，不 lseek 会追加到文件末尾变成第二个头
          fileIo.lseek(this.recFile.fd, 0, 0);
          this.writeWavHeader(this.recFile.fd, dataSize);
          hilog.info(DOMAIN, TAG, 'stopRec 写入 WAV dataSize=%{public}d 字节', dataSize);
        } catch (e) { /* ignore */ }
        try { fileIo.closeSync(this.recFile.fd); } catch (e) { /* ignore */ }
        this.recFile = undefined;
      }
      this.recDuration = this.sec;   // 记录本次录音时长（秒），供回放有界计时
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'stopRec fail: %{public}s', err.message);
    }
      this.recording = false;
      this.hasFile = this.fileExists();
      this.stopRealtimeAsr();   // 结束实时识别并保存文字稿
    }

  // 把 readData 的 PCM 块按 1280 字节切片喂给识别引擎（writeAudio 仅支持 640/1280，末块补零）。
  // 必须在 startListening 成功（onStart 触发 → asrListening=true）后才能调用，否则报 1002200010。
  private feedAsr(buffer: ArrayBuffer): void {
    if (!this.asrEngine || !this.asrSession || !this.asrListening) return;
    const full: Uint8Array = new Uint8Array(buffer);
    const CHUNK: number = 1280;
    for (let off: number = 0; off < full.length; off += CHUNK) {
      const end: number = Math.min(off + CHUNK, full.length);
      const slice: Uint8Array = full.subarray(off, end);
      let chunk: Uint8Array;
      if (slice.length < CHUNK) {
        chunk = new Uint8Array(CHUNK);
        chunk.set(slice);
      } else {
        chunk = slice;
      }
      try {
        this.asrEngine.writeAudio(this.asrSession, chunk);
      } catch (e) {
        const ce = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'asr writeAudio fail: %{public}s', ce.message);
      }
    }
  }

  // 启动实时语音识别：创建引擎 → 设监听 → startListening，文字持续写入 liveText
  private startRealtimeAsr(): void {
    const extraParam: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'long' };
    const initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,                       // Core Speech Kit 当前仅支持离线识别
      extraParams: extraParam
    };
    speechRecognizer.createEngine(initParams, (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine): void => {
      if (err || !engine) {
        this.asrError = '语音识别引擎初始化失败（' + (err ? (err.code + ':' + err.message) : '空引擎') + '）。Core Speech Kit 仅支持离线识别；若已下载中文离线模型仍失败，多为本机缺失离线识别运行时（libhiai_ir_infershape.so）。可直接在下方手动录入转写文字稿，或更换设备重试。';
        hilog.error(DOMAIN, TAG, 'asr createEngine fail: %{public}s', this.asrError);
        return;
      }
      this.asrEngine = engine;
      this.asrSession = 'live_' + Date.now().toString();
      // 兜底：若引擎既无 onStart 也无 onError（离线识别运行时未就绪），8s 后置错误并释放，避免静默卡死
      this.clearAsrGuard();
      this.asrGuard = setTimeout((): void => {
        this.asrGuard = 0;
        if (!this.asrListening) {
          this.asrError = '离线识别启动超时（设备离线识别运行时未就绪或缺失），可尝试在系统「设置→智慧语音」确认中文离线模型已启用，或直接手动录入转写文字稿、更换设备重试。';
          if (this.asrEngine) {
            try { this.asrEngine.shutdown(); } catch (e) { /* ignore */ }
            this.asrEngine = undefined;
          }
          this.asrSession = '';
          this.asrListening = false;
        }
      }, 8000);
      engine.setListener({
        // onStart = startListening 成功！此时才允许 writeAudio（SDK 强约束）。
        onStart: (_sid: string, _msg: string): void => {
          this.clearAsrGuard();
          this.asrListening = true;
        },
        onEvent: (_sid: string, _code: number, _msg: string): void => { /* 忽略内部事件 */ },
        onResult: (_sid: string, result: speechRecognizer.SpeechRecognitionResult): void => {
          // result.isFinal=true 为整句结束；否则为当前句的中间结果
          if (result.isFinal) {
            this.asrCommitted += result.result;
            this.liveText = this.asrCommitted;
          } else {
            this.liveText = this.asrCommitted + result.result;
          }
        },
        onComplete: (_sid: string, _msg: string): void => {
          this.clearAsrGuard();
          if (this.asrEngine) {
            try { this.asrEngine.shutdown(); } catch (e) { /* ignore */ }
            this.asrEngine = undefined;
          }
          this.asrListening = false;
        },
        onError: (_sid: string, code: number, msg: string): void => {
          this.clearAsrGuard();
          this.asrError = '识别出错(' + code + '): ' + msg;
          hilog.error(DOMAIN, TAG, 'asr onError: %{public}s', this.asrError);
          if (this.asrEngine) {
            try { this.asrEngine.shutdown(); } catch (e) { /* ignore */ }
            this.asrEngine = undefined;
          }
          this.asrSession = '';
          this.asrListening = false;
        }
      });
      const audioInfo: speechRecognizer.AudioInfo = { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 };
      const startParams: speechRecognizer.StartParams = {
        sessionId: this.asrSession,
        audioInfo: audioInfo,
        extraParams: { 'recognitionMode': 1, 'maxAudioDuration': 600000 }
      };
      // startListening 返回 void，失败通过 onError 回调上报；同步 try/catch 仅捕获参数错误
      try {
        engine.startListening(startParams);
      } catch (e) {
        const ce = e as BusinessError;
        this.asrError = '启动识别失败：' + ce.message;
        if (this.asrEngine) {
          try { this.asrEngine.shutdown(); } catch (e2) { /* ignore */ }
          this.asrEngine = undefined;
        }
        this.asrSession = '';
      }
    });
  }

  private clearAsrGuard(): void {
    if (this.asrGuard !== 0) {
      clearTimeout(this.asrGuard);
      this.asrGuard = 0;
    }
  }

  // 停止实时识别：finish 收尾，并把已识别文字存本机（供详情页「我的口述转写」持久化）
  private stopRealtimeAsr(): void {
    this.clearAsrGuard();
    const eng = this.asrEngine;
    const sid = this.asrSession;
    this.asrEngine = undefined;
    this.asrSession = '';
    if (eng && sid) {
      try { eng.finish(sid); } catch (e) { /* ignore */ }
      try { eng.shutdown(); } catch (e) { /* ignore */ }
    }
    this.commitLiveTranscript();
  }

  // 把实时识别结果（或手动录入的兜底文字）写入本机 txt（供详情页持久化展示）；仅在确有文字时写入
  private commitLiveTranscript(): void {
    // ASR 失败时优先取手动录入的文字稿；识别成功时取 liveText
    const text: string = (this.asrError ? this.manualText : this.liveText).trim();
    if (text.length === 0) return;
    try {
      const fd = fileIo.openSync(
        this.transcriptPath(),
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(fd.fd, text);
      fileIo.closeSync(fd.fd);
      hilog.info(DOMAIN, TAG, 'commitLiveTranscript 写入 %{public}d 字', text.length);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'commitLiveTranscript fail');
    }
  }

  // 回放：创建 AVPlayer → 设置 fd 源 → 待 stateChange 到 prepared 再 play
  // ⚠️ 关键修复：AVPlayer 是异步状态机，必须等 'prepared' 后调用 play() 才会真正出声；
  //    原代码在设置 url 后立刻 play()，此时播放器还在 idle/initialized，调用被忽略 → 回放完全无声。
  //    改用 fdSrc（带 offset/length）比 url('fd://') 更稳，避免读到错误区间。
  private async play(): Promise<void> {
    if (this.playing) {
      this.stopPlay();
      return;
    }
    if (!this.hasFile) {
      return;
    }
    // 释放上一次已结束但未释放的播放器（如 completed 后未 replay），避免句柄泄漏
    if (this.avPlayer) {
      try { this.avPlayer.release(); } catch (e) { /* ignore */ }
      this.avPlayer = undefined;
    }
    if (this.playFile) {
      try { fileIo.closeSync(this.playFile.fd); } catch (e) { /* ignore */ }
      this.playFile = undefined;
    }
    try {
      const path: string = this.filePath();
      const stat = fileIo.statSync(path);
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      this.playFile = file;
      this.playing = true;
      this.paused = false;
      this.sec = 0;
      const player: media.AVPlayer = await media.createAVPlayer();
      this.avPlayer = player;
      player.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'avPlayer error: %{public}s', err.message);
        this.playing = false;
        this.stopTick();
        this.sec = 0;
      });
      player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        hilog.info(DOMAIN, TAG, 'avPlayer stateChange=%{public}s', state);
        if (state === 'initialized') {
          // fd 源设置后进入 initialized，需主动 prepare 才能进入 prepared
          try { player.prepare(); } catch (e) { /* ignore */ }
        } else if (state === 'prepared') {
          try { player.play(); } catch (e) { /* ignore */ }
        } else if (state === 'completed') {
          this.playing = false;
          this.paused = false;
          this.stopTick();
          this.sec = 0;
          try { player.release(); } catch (e) { /* ignore */ }
          this.avPlayer = undefined;
        }
      });
      // 设置 fd 源（带 offset/length），触发 stateChange 状态机推进到 prepared
      player.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
      this.startTick('play');   // 有界回放计时：到录音时长自动停止
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'play fail: %{public}s', err.message);
      this.playing = false;
    }
  }

  private stopPlay(): void {
    this.stopTick();
    try {
      if (this.avPlayer) {
        try { this.avPlayer.stop(); } catch (e) { /* ignore */ }
        try { this.avPlayer.release(); } catch (e) { /* ignore */ }
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
    this.paused = false;
    this.sec = 0;
  }

  // 暂停回放：停在当前位置，保留 sec 进度，可继续
  private pausePlay(): void {
    if (!this.avPlayer || !this.playing) {
      return;
    }
    try { this.avPlayer.pause(); } catch (e) { /* ignore */ }
    this.playing = false;
    this.paused = true;
    this.stopTick();   // 冻结进度（保留 sec）
  }

  // 继续回放：从暂停处接着播，进度沿用当前 sec
  private resumePlay(): void {
    if (!this.avPlayer || !this.paused) {
      return;
    }
    try { this.avPlayer.play(); } catch (e) { /* ignore */ }
    this.playing = true;
    this.paused = false;
    this.startTick('play');   // 从当前 sec 继续计时
  }

  // 强制复位（切题 / 离开页面）：释放资源、关闭 fd、复位状态
  private forceStop(): void {
    this.stopTick();
    this.recording = false;
    this.playing = false;
    this.paused = false;
    this.sec = 0;
    if (this.audioCapturer) {
      this.audioCapturer.release().then((): void => {}).catch((): void => {});
      this.audioCapturer = undefined;
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
        if (this.permDenied) {
          Button('麦克风未授权，重试或去设置')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.warning'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .onClick(() => this.requestPerm())
        } else {
          Button('授权麦克风，开始开口练习')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .onClick(() => this.requestPerm())
        }
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

        // 回放控制：未播→回放；播放中→暂停/停止；已暂停→继续/停止
        if (this.hasFile) {
          Row({ space: 10 }) {
            if (this.playing) {
              Button('暂停')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.warning'))
                .fontColor($r('app.color.on_primary'))
                .borderRadius(RADIUS.pill)
                .onClick(() => this.pausePlay())
              Button('停止')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.surface_variant'))
                .fontColor($r('app.color.text_primary'))
                .borderRadius(RADIUS.pill)
                .onClick(() => this.stopPlay())
            } else if (this.paused) {
              Button('继续')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.on_primary'))
                .borderRadius(RADIUS.pill)
                .onClick(() => this.resumePlay())
              Button('停止')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.surface_variant'))
                .fontColor($r('app.color.text_primary'))
                .borderRadius(RADIUS.pill)
                .onClick(() => this.stopPlay())
            } else {
              Button('回放')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.surface_variant'))
                .fontColor($r('app.color.text_primary'))
                .borderRadius(RADIUS.pill)
                .onClick(() => this.play())
            }
          }
          .width('100%')
          .margin({ top: SPACE.xs })
        }

        Text(
          (this.recording ? '录音中 ' :
            (this.playing ? '回放中 ' :
              (this.paused ? '已暂停 ' :
                (this.hasFile ? '上次录音 ' : '')))) + this.fmt(this.sec)
        )
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ top: SPACE.xs })

        // 实时语音转写窗口（我们自己渲染的 Text，保证一定可见）：录音中实时显示识别文字，
        // 识别失败也显示原因，并提供可编辑文本框供手动录入/粘贴转写结果，保证交付。
        if (this.captionShown) {
          Column() {
            Row({ space: 6 }) {
              Text('实时转写（语音→文字）')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.text_secondary'))
              if (this.recording) {
                Text('● 识别中')
                  .fontSize(FONT.caption)
                  .fontColor($r('app.color.danger'))
              } else if (this.liveText) {
                Text('✓ 已转写')
                  .fontSize(FONT.caption)
                  .fontColor($r('app.color.brand'))
              }
            }
            .width('100%')
            .margin({ bottom: 4 })
            // 1. 识别状态 / 错误说明
            if (this.asrError) {
              Text(this.asrError + '；可点击下方文本框手动录入/粘贴口述内容，录音结束后会一并保存。')
                .width('100%')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.danger'))
                .lineHeight(20)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(RADIUS.md)
                .padding(10)
                .alignSelf(ItemAlign.Start)
            } else if (this.liveText) {
              Text(this.liveText)
                .width('100%')
                .fontSize(FONT.body)
                .fontColor($r('app.color.text_body'))
                .lineHeight(22)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(RADIUS.md)
                .padding(10)
                .alignSelf(ItemAlign.Start)
            } else {
              Text('正在聆听，请开始口述作答…')
                .width('100%')
                .fontSize(FONT.body)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(22)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(RADIUS.md)
                .padding(10)
                .alignSelf(ItemAlign.Start)
            }
            // 2. 可编辑文本框：识别失败时手动录入；识别成功时可在此基础上修订
            TextArea({ placeholder: this.asrError ? '本设备未预置中文语音模型，可在此手动录入转写文字稿…' : '可在识别结果上修订…', text: this.asrError ? this.manualText : this.liveText })
              .width('100%')
              .height(80)
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .backgroundColor($r('app.color.surface'))
              .borderRadius(RADIUS.md)
              .margin({ top: 6 })
              .onChange((value: string): void => {
                if (this.asrError) {
                  this.manualText = value;
                } else {
                  this.liveText = value;
                }
              })
          }
          .width('100%')
          .margin({ top: SPACE.xs })
        }

        if (this.hasTranscript && !this.captionShown) {
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

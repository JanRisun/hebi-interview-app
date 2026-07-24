// 视频作答页：摄像头预览 + 思考计时 + 录制视频 + 试题详情可展开
// 参考图：
//   态1（图1）：顶部栏（关闭 + 思考时间 + 重新计时 + 翻转）+ 摄像头预览 + 人脸识别虚线框
//              + 底部上滑的试题详情半屏卡片（可折叠）
//   态2（图2）：顶部栏同上 + 摄像头预览 + 人脸识别框 + 最佳拍摄区域弧形提示
//              + 录制时间 + 录制按钮 + 看题按钮（点击展开态1）
// 录制基于 CameraKit 的 VideoOutput；预览走 XComponent 接收 PreviewOutput 的 surface。
// 文件最终落到 filesDir；存答题记录到 preferences 'practice'（key 前缀 v_）。
import { camera } from '@kit.CameraKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DataStore } from '../model/DataStore';
import { AnswerRecord, Question } from '../model/Types';
import { FONT, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

const DOMAIN: number = 0x0001;
const TAG: string = 'VideoAnswer';
// 作答时长上限（秒），到点自动停止录制
const MAX_REC_SEC: number = 300;

// XComponent 控制器子类：重写 onSurfaceCreated（ArkTS 严格模式禁止重赋值方法，故用子类 + 普通回调字段）
class CameraXComponentController extends XComponentController {
  surfaceCreatedCallback: ((surfaceId: string) => void) | null = null;

  onSurfaceCreated(surfaceId: string): void {
    this.surfaceCreatedCallback?.(surfaceId);
  }
}

// 录制回看页跳转参数（规避 arkts-no-untyped-obj-literals）
interface VideoReviewParam { videoPath: string }

@Component
export struct VideoAnswerView {
  @State question: Question | null = null;
  @State showQuestion: boolean = false;       // 是否展开试题详情卡片
  @State thinkElapsed: number = 0;            // 思考已用秒（正计时）
  @State thinkActive: boolean = false;
  @State recording: boolean = false;          // 是否正在录制
  @State recSec: number = 0;                  // 录制已用秒
  @State isFrontCamera: boolean = true;       // 当前是否前置摄像头
  @State cameraReady: boolean = false;        // 相机是否初始化完成
  @State surfaceId: string = '';              // XComponent 的 surface id
  @State permChecked: boolean = false;        // 是否已完成权限检查

  @Prop params: Object;
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  @Consume pageStack: NavPathStack;

  // CameraKit 相关
  private cameraInitStarted: boolean = false;   // 防止 surface/权限两条路径重复初始化相机
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private videoOutput: camera.VideoOutput | null = null;
  private session: camera.Session | null = null;
  private avRecorder: media.AVRecorder | null = null;
  private videoFileFd: number = -1;
  private videoPath: string = '';

  // XComponent 控制器：通过 onSurfaceCreated 回调拿到 surfaceId
  private xComponentController: CameraXComponentController = new CameraXComponentController();

  // 计时器
  private thinkTimer: number = 0;
  private recTimer: number = 0;

  // 由 VideoReview 返回时通过 AppStorage 信号触发复位（兜底，保证 onPageShow 未触发也能重录）
  @StorageLink('vaReset') @Watch('onVaReset') vaReset: number = 0;

  aboutToAppear(): void {
    // 注册 surface 创建回调，拿到 surfaceId 后再初始化相机
    this.xComponentController.surfaceCreatedCallback = (surfaceId: string): void => {
      this.surfaceId = surfaceId;
      this.initCamera();
    };
    const p = (this.params ?? {}) as Record<string, Object>;
    const id: string = (p['id'] as string) ?? '';
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then(() => {
      this.question = DataStore.questionById(id) ?? null;
    });
    this.startThinkTimer();
    this.checkAndRequestPermissions();
  }

  aboutToDisappear(): void {
    this.stopThinkTimer();
    this.stopRecTimer();
    // 离开页面停止录制并释放相机
    if (this.recording) {
      this.videoOutput?.stop().catch(() => { /* ignore */ });
      this.recording = false;
    }
    this.releaseCamera();
  }

  // 离开本页（跳回看页 / 返回上级）时释放相机，避免占用并复位状态
  onPageHide(): void {
    this.stopRecTimer();
    this.releaseCamera();
  }

  // 从回看页（重录 / 关闭）返回本页时触发，重置录制状态并重新初始化相机，
  // 否则旧 AVRecorder 停在 STOPPED 态，再次 start() 会报 "not permit in current state"，且录制计时未复位。
  onPageShow(): void {
    this.prepareForReRecord();
  }

  // 与 onPageShow 同效，由 VideoReview 在返回前通过 AppStorage 信号触发（兜底，避免 onPageShow 未触发导致卡死）
  private onVaReset(): void {
    this.prepareForReRecord();
  }

  // 重置录制状态并重新初始化相机，使可再次录制。
  // 注意：重录不重置「思考计时」，沿用首次作答的思考用时（故不触碰 thinkElapsed / thinkActive）。
  private prepareForReRecord(): void {
    this.recording = false;
    this.recSec = 0;
    this.stopRecTimer();
    this.cameraInitStarted = false;
    this.releaseCamera().then(() => {
      this.initCamera();
    });
  }

  // ---- 思考时间 ----
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

  private resetThinkTimer(): void {
    this.stopThinkTimer();
    this.thinkElapsed = 0;
    this.startThinkTimer();
  }

  // ---- 录制计时 ----
  private startRecTimer(): void {
    if (this.recTimer !== 0) return;
    const tick = (): void => {
      this.recSec += 1;
      if (this.recSec >= MAX_REC_SEC) {
        // 到达上限自动停止
        this.toggleRecording();
        promptAction.showToast({ message: '已达作答时长上限', duration: 1500 });
        return;
      }
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

  // ---- 权限 ----
  private async checkAndRequestPermissions(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = await this.getTokenId();
      const cam: abilityAccessCtrl.GrantStatus =
        await atManager.checkAccessToken(tokenId, 'ohos.permission.CAMERA');
      const mic: abilityAccessCtrl.GrantStatus =
        await atManager.checkAccessToken(tokenId, 'ohos.permission.MICROPHONE');
      if (cam === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
        mic === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        // 权限 OK，等待 surface 就绪再 initCamera（surface 由 XComponent onLoad 提供）
      } else {
        await this.requestPermissions();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'checkAndRequestPermissions fail');
    }
    this.permChecked = true;
    this.initCamera();
  }

  private async requestPermissions(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(ctx, [
        'ohos.permission.CAMERA',
        'ohos.permission.MICROPHONE'
      ]);
      if (result.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ||
        result.authResults[1] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        promptAction.showToast({ message: '需要相机和麦克风权限', duration: 1500 });
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermissions fail: %{public}s', err.message);
    }
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

  // ---- CameraKit：预览 + 录像 ----
  private async initCamera(): Promise<void> {
    if (this.cameraInitStarted || !this.surfaceId || !this.permChecked) return;
    this.cameraInitStarted = true;
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      this.cameraManager = camera.getCameraManager(ctx);
      const cameras: camera.CameraDevice[] = this.cameraManager.getSupportedCameras();
      if (cameras.length === 0) {
        promptAction.showToast({ message: '未找到摄像头', duration: 1500 });
        return;
      }
      const wantPos: camera.CameraPosition =
        this.isFrontCamera ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
      const cam: camera.CameraDevice =
        cameras.find((c) => c.cameraPosition === wantPos) || cameras[0];
      this.cameraInput = this.cameraManager.createCameraInput(cam);
      await this.cameraInput.open();

      // 预览输出 → XComponent surface
      const capability: camera.CameraOutputCapability =
        this.cameraManager.getSupportedOutputCapability(cam);
      const previewProfiles: camera.Profile[] = capability.previewProfiles;
      if (previewProfiles.length === 0) return;
      const previewProfile: camera.Profile = previewProfiles[0];
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, this.surfaceId);
      // 让预览画面保持相机分辨率的宽高比，避免人物被拉伸
      this.adjustPreviewSurface(previewProfile);

      // 录像输出（AVRecorder 提供输入 surface，落地到本机文件）
      const videoProfiles: camera.VideoProfile[] = capability.videoProfiles;
      if (videoProfiles.length === 0) {
        promptAction.showToast({ message: '当前摄像头不支持视频录制', duration: 1500 });
        return;
      }
      const videoProfile: camera.VideoProfile = videoProfiles[0];
      // 在 filesDir 创建录制文件
      this.videoPath = ctx.filesDir + '/video_' + Date.now() + '.mp4';
      const file = fileIo.openSync(
        this.videoPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE
      );
      this.videoFileFd = file.fd;
      const avProfile: media.AVRecorderProfile = {
        fileFormat: media.ContainerFormatType.CFT_MPEG_4,
        audioBitrate: 48000,
        audioChannels: 1,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: 48000,
        videoBitrate: 6000000,
        videoCodec: media.CodecMimeType.VIDEO_AVC,
        videoFrameWidth: videoProfile.size.width,
        videoFrameHeight: videoProfile.size.height,
        videoFrameRate: 30
      };
      const avConfig: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
        profile: avProfile,
        url: 'fd://' + file.fd,
        rotation: 0
      };
      const avRecorder: media.AVRecorder = await media.createAVRecorder();
      this.avRecorder = avRecorder;
      await avRecorder.prepare(avConfig);
      // 取 AVRecorder 的输入 surface，作为录像输出目标
      const videoSurfaceId: string = await avRecorder.getInputSurface();
      this.videoOutput = this.cameraManager.createVideoOutput(videoProfile, videoSurfaceId);

      // 构建录像会话（NORMAL_VIDEO 场景）
      const session: camera.Session = this.cameraManager.createSession(camera.SceneMode.NORMAL_VIDEO);
      this.session = session;
      const cameraInput: camera.CameraInput | null = this.cameraInput;
      const previewOutput: camera.PreviewOutput | null = this.previewOutput;
      const videoOutput: camera.VideoOutput | null = this.videoOutput;
      if (!cameraInput || !previewOutput || !videoOutput) {
        return;
      }
      session.beginConfig();
      session.addInput(cameraInput);
      session.addOutput(previewOutput);
      session.addOutput(videoOutput);
      await session.commitConfig();
      await session.start();
      this.cameraReady = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'initCamera fail: %{public}s', err.message);
      promptAction.showToast({ message: '摄像头初始化失败：' + err.message, duration: 2000 });
      this.cameraReady = false;
      this.cameraInitStarted = false; // 复位，允许失败后重试（如再次翻转）
    }
  }

  // 调整预览 surface 的显示区域，使其宽高比与所选预览分辨率一致，避免画面被拉伸变形
  // 采用 cover 适配：铺满可用区域、溢出部分由屏幕裁切，预览更高更饱满且上下等距居中
  private adjustPreviewSurface(profile: camera.Profile): void {
    try {
      const rect = this.xComponentController.getXComponentSurfaceRect();
      const containerW: number = rect.surfaceWidth;
      const containerH: number = rect.surfaceHeight;
      const pw: number = profile.size.width;
      const ph: number = profile.size.height;
      if (containerW <= 0 || containerH <= 0 || pw <= 0 || ph <= 0) {
        return;
      }
      const profileRatio: number = pw / ph;       // 预览分辨率宽高比
      const containerRatio: number = containerW / containerH; // 容器（XComponent）宽高比
      let w: number;
      let h: number;
      if (profileRatio > containerRatio) {
        // 预览更宽：以高度铺满，宽度按比例溢出（左右由屏幕裁切），画面更高
        h = containerH;
        w = Math.round(containerH * profileRatio);
      } else {
        // 预览更高：以宽度铺满，高度按比例溢出（上下由屏幕裁切）
        w = containerW;
        h = Math.round(containerW / profileRatio);
      }
      // 不设置 offsetX/offsetY，surface 自动居中 → 上下（左右）等距
      this.xComponentController.setXComponentSurfaceRect({ surfaceWidth: w, surfaceHeight: h });
    } catch (e) {
      // 调整失败不影响主流程
    }
  }

  private async releaseCamera(): Promise<void> {
    try {
      if (this.session) {
        await this.session.stop().catch(() => { /* ignore */ });
        this.session = null;
      }
      if (this.previewOutput) {
        await this.previewOutput.release().catch(() => { /* ignore */ });
        this.previewOutput = null;
      }
      if (this.videoOutput) {
        await this.videoOutput.release().catch(() => { /* ignore */ });
        this.videoOutput = null;
      }
      if (this.cameraInput) {
        await this.cameraInput.close().catch(() => { /* ignore */ });
        this.cameraInput = null;
      }
      if (this.avRecorder) {
        await this.avRecorder.release().catch(() => { /* ignore */ });
        this.avRecorder = null;
      }
      if (this.videoFileFd >= 0) {
        try {
          fileIo.closeSync(this.videoFileFd);
        } catch (e) { /* ignore */ }
        this.videoFileFd = -1;
      }
    } catch (e) { /* ignore */ }
    this.cameraReady = false;
    // 复位防重入标志，确保翻转后能重新初始化相机
    this.cameraInitStarted = false;
  }

  // 翻转前后摄像头
  private async flipCamera(): Promise<void> {
    this.isFrontCamera = !this.isFrontCamera;
    await this.releaseCamera();
    this.initCamera();
  }

  // ---- 录制控制 ----
  private async toggleRecording(): Promise<void> {
    if (!this.cameraReady || !this.videoOutput) {
      promptAction.showToast({ message: '摄像头未就绪，请稍候', duration: 1200 });
      return;
    }
    try {
    if (this.recording) {
      await this.videoOutput.stop();
      await this.avRecorder?.stop();
      this.recording = false;
      this.stopRecTimer();
      await this.saveAnswerRecord();
      // 跳转到录制回看页：用户可重录或进入下一步
      const reviewParams: VideoReviewParam = { videoPath: this.videoPath };
      this.pageStack.pushPathByName('VideoReview', reviewParams);
    } else {
        await this.avRecorder?.start();
        await this.videoOutput.start();
        this.recording = true;
        this.recSec = 0;
        this.stopThinkTimer(); // 开始录制即锁定思考时间，留存用于答题分析
        this.startRecTimer();
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'toggleRecording fail: %{public}s', err.message);
      promptAction.showToast({ message: '录制失败：' + err.message, duration: 2000 });
    }
  }

  // ---- 保存答题记录 ----
  private async saveAnswerRecord(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const prefs = await preferences.getPreferences(ctx, 'practice');
      const id: string = this.question ? this.question.id : 'unknown';
      const rec: AnswerRecord = {
        id: id,
        title: this.question ? this.question.title : '',
        thinkSec: this.thinkElapsed,
        speakSec: this.recSec,
        date: this.nowStr(),
        audioPath: this.videoPath
      };
      prefs.putSync('v_' + id, JSON.stringify(rec));
      const raw: string = prefs.getSync('v_ids', '') as string;
      const ids: string[] = raw ? raw.split(',') : [];
      if (ids.indexOf(id) < 0) {
        ids.push(id);
        prefs.putSync('v_ids', ids.join(','));
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

  private fmt(s: number): string {
    const m: number = Math.floor(s / 60);
    const ss: number = s % 60;
    return m + ':' + (ss < 10 ? '0' + ss : '' + ss);
  }

  private submitReview(): void {
    promptAction.showToast({ message: '已提交点评，AI 正在分析…', duration: 2000 });
  }

  // ---- UI 构建器 ----

  // 人脸识别虚线框 + 中心十字（静态，固定居中）
  @Builder faceFrame() {
    Stack({ alignContent: Alignment.Center }) {
      // 中心水平线
      Column()
        .width(50)
        .height(1.5)
        .backgroundColor(Color.White)
      // 中心垂直线（叠加在 Column 上偏移实现十字）
      Column()
        .width(1.5)
        .height(50)
        .backgroundColor(Color.White)
        .offset({ x: 0, y: 0 })
      // 椭圆虚线框（人脸框）
      Column()
        .width('58%')
        .height('38%')
        .border({
          width: 2,
          color: '#80FFFFFF',
          style: BorderStyle.Dashed
        })
        .borderRadius(200)
    }
    .width('100%')
    .height('100%')
  }

  // 顶部栏：关闭 + 思考时间 + 重新计时胶囊 + 翻转
  @Builder topBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(22)
        .fontColor([Color.White])
        .onClick(() => {
          this.pageStack.pop();
        })
      Blank()
      Row() {
        Text('🕐')
          .fontSize(12)
          .fontColor(Color.White)
          .margin({ right: 4 })
        Text('思考时间 ' + this.fmt(this.thinkElapsed))
          .fontSize(13)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
      }
      .padding({ left: SPACE.md, right: SPACE.md, top: 6, bottom: 6 })
      .backgroundColor('rgba(255,255,255,0.12)')
      .borderRadius(20)
      Blank()
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
          .fontSize(13)
          .fontColor([$r('app.color.danger')])
          .scale({ x: 1.2, y: 1.2 })
          .margin({ right: 4 })
        Text('重新计时')
          .fontSize(13)
          .fontColor($r('app.color.danger'))
      }
      .padding({ left: SPACE.md, right: SPACE.md, top: 6, bottom: 6 })
      .border({ width: 1.5, color: $r('app.color.danger'), style: BorderStyle.Solid })
      .borderRadius(20)
      .enabled(!this.recording) // 录制中锁定，避免误改已留存的思考时间
      .opacity(this.recording ? 0.4 : 1)
      .onClick(() => {
        this.resetThinkTimer();
      })
      Blank()
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_triangle_2_circlepath_camera'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.15)')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.flipCamera();
      })
    }
    .width('100%')
    .padding({
      left: SPACE.lg,
      right: SPACE.lg,
      top: this.safeTop + SPACE.sm,
      bottom: SPACE.sm
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.85)')
    .position({ x: 0, y: 0 })  // 顶层 Stack 默认 alignContent=Bottom，这里强制锚定到顶部
  }

  // 最佳拍摄区域：弧形虚线 + 文字（位于人物胸部上方，半透明）
  @Builder bestAreaHint() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('85%')
        .height(180)
        .border({
          width: 1.5,
          color: 'rgba(255,255,255,0.6)',
          style: BorderStyle.Dashed
        })
        .borderRadius({ topLeft: 160, topRight: 160, bottomLeft: 20, bottomRight: 20 })
        .backgroundColor('rgba(255,255,255,0.04)')
      Text('最佳拍摄区域')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.7)')
        .margin({ bottom: 16 })
    }
    .width('85%')
    .height(180)
  }

  // 录制控件：底部左看题 + 中录制按钮 + 上方时间
  @Builder recordingControls() {
    Column() {
      // 录制时间
      Row() {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.recording ? $r('app.color.danger') : Color.White)
          .margin({ right: SPACE.sm })
        Text(this.fmt(this.recSec) + ' / ' + this.fmt(MAX_REC_SEC))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: SPACE.lg })

      Row() {
        // 左下：看题按钮
        Column() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(20)
            .fontColor([Color.White])
          Text('看题')
            .fontSize(12)
            .fontColor(Color.White)
            .margin({ top: 4 })
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(28)
        .backgroundColor('rgba(255,255,255,0.15)')
        .onClick(() => {
          this.showQuestion = true;
        })

        Blank()

        // 中下：录制大按钮
        Column() {
          if (this.recording) {
            // 录制中：白色圆角方块（停止）
            Column()
              .width(28)
              .height(28)
              .borderRadius(6)
              .backgroundColor($r('app.color.danger'))
          } else {
            // 未录制：红色摄像机图标
            SymbolGlyph($r('sys.symbol.camera_fill'))
              .fontSize(32)
              .fontColor([$r('app.color.danger')])
          }
        }
        .width(72)
        .height(72)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(36)
        .backgroundColor(Color.White)
        .shadow({ radius: 16, color: 'rgba(0,0,0,0.4)', offsetY: 4 })
        .scale({ x: this.recording ? 0.92 : 1, y: this.recording ? 0.92 : 1 })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          this.toggleRecording();
        })

        Blank()

        // 右下：提交点评按钮（录制后才有意义，无录像时也允许点，按 toast 处理）
        Column() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([Color.White])
          Text('点评')
            .fontSize(12)
            .fontColor(Color.White)
            .margin({ top: 4 })
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(28)
        .backgroundColor('rgba(255,255,255,0.15)')
        .onClick(() => {
          this.submitReview();
        })
      }
      .width('100%')
      .padding({ left: SPACE.lg, right: SPACE.lg })
      .margin({ bottom: SPACE.md })

      Text(this.recording ? '正在录制，点击后完成录制' : '点击开始录制')
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.7)')
        .margin({ bottom: this.safeBottom + SPACE.md })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // 试题详情半屏卡片（从底部上滑），与图1一致
  @Builder questionPanel() {
    Column() {
      // 把手 + 标题
      Row() {
        Column()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor('rgba(0,0,0,0.15)')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: SPACE.sm, bottom: SPACE.sm })

      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
        Blank()
        Text('试题详情')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Blank()
        // 占位以平衡左右空间
        Column().width(20)
      }
      .width('100%')
      .padding({ left: SPACE.lg, right: SPACE.lg, bottom: SPACE.sm })
      .onClick(() => {
        this.showQuestion = false;
      })

      Scroll() {
        Column() {
          if (this.question) {
            Text('问题')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: SPACE.xs })
            Text(this.question.title)
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title'))
              .margin({ bottom: SPACE.md })
              .alignSelf(ItemAlign.Start)
            Text(this.question.prompt)
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.text_body'))
              .lineHeight(22)
              .alignSelf(ItemAlign.Start)
          } else {
            Text('题目加载中…')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .padding({ left: SPACE.lg, right: SPACE.lg })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('34%')
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.35)', offsetY: -4 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 黑色底 + 摄像头预览
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)

        XComponent({
          id: 'camera_preview',
          type: 'surface',
          controller: this.xComponentController
        })
          .onDestroy(() => {
            this.releaseCamera();
          })
          .width('100%')
          .height('100%')

        // 人脸识别虚线框
        this.faceFrame()
      }
      .width('100%')
      .height('100%')

      // 底部：展开试题详情 OR 录制控件 + 最佳拍摄区域
      if (this.showQuestion) {
        this.questionPanel()
      } else {
        Column() {
          Blank().layoutWeight(1)
          this.bestAreaHint()
          Blank().layoutWeight(1)
          this.recordingControls()
        }
        .width('100%')
        .height('100%')
      }

      // 顶部栏：置于 Stack 最后（最上层），避免被全屏底部容器拦截点击
      this.topBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
  }
}
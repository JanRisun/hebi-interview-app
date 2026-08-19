// 主框架：知识库 / 速记卡 / 题库 / 个人中心
// 底部导航栏参考 HarmonyOS_Samples/SmartReach 的「智感握持」思路：
//   - 悬浮式胶囊底栏（Swiper + 自定义浮层，圆角 + 阴影 + 底部浮起）
//   - 通过 @kit.MultimodalAwarenessKit 的 motion 感知 API 检测握持手（API 20+ 可用），
//     左手握持时底栏左移、右手握持时右移，靠近持机手拇指（智感握持跟手），
//     仅折叠屏设备（deviceType === 'foldable'）启用；普通直板手机固定居中，不做偏移
//     （折叠屏单手够不到对侧，跟手更实用；非折叠屏无需申请权限、保持居中更稳妥）
//   - 选中项由官方 Particle 组件触发爆裂粒子特效 + springCurve 图标回弹（已验证可编译）
// 子页（Detail / Knowledge / Favorites 等）由 Navigation 的 pageStack 推入，
// 推入后首页（含悬浮 Tab 栏）被隐藏，因此子页无需为 Tab 栏预留额外高度。
// SymbolGlyph 是 ArkUI 内置组件（同 Text/Image/Column），无需从 kit 导入
import { CategoryView } from './Category';
import { FlashcardView } from './Flashcard';
import { PracticeView } from './Practice';
import { ProfileView } from './Profile';
import { Detail } from './Detail';
import { SearchPage } from './Search';
import { Favorites } from './Favorites';
import { FlashcardCollection } from './FlashcardCollection';
import { KnowledgeView } from './Knowledge';
import { QuestionBankView } from './QuestionBank';
import { MyMarkView } from './MyMark';
import { StudyRecord } from './StudyRecord';
import { ExamRecord } from './ExamRecord';
import { StudyPlan } from './StudyPlan';
import { AudioAnswerView } from './AudioAnswer';
import { AudioReviewView } from './AudioReview';
import { SettingsView } from './Settings';
import { VideoAnswerView } from './VideoAnswer';
import { VideoReviewView } from './VideoReview';
import { TestLabView } from './TestLab';
import { AICaptionDemoView } from './AICaptionDemo';
import { SpeechRecognizerDemoView } from './SpeechRecognizerDemo';
import { LocalKnowledgeView } from './LocalKnowledge';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { FONT, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES, RADIUS } from '../utils/Theme';
import { applyStatusBar } from '../utils/StatusBar';
import { curves } from '@kit.ArkUI';
import { motion } from '@kit.MultimodalAwarenessKit';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import deviceInfo from '@ohos.deviceInfo';

// 隐私政策地址（AppGallery 上架必填，托管于 GitHub Pages 公开站点）
const PRIVACY_POLICY_URL: string = 'https://janrisun.github.io/hebi-interview-app/privacy.html';

// 弹簧曲线（选中回弹反馈）
const SPRING_CURVE = curves.springCurve(0, 1, 228, 30);

// 悬浮底栏参数：底部浮起边距 + 栏自身高度 = 主 Tab 内容需预留的底部空间，避免被悬浮栏遮挡
const BAR_BOTTOM_MARGIN: number = 14;
const FLOATING_BAR_HEIGHT: number = 60;
// 底栏宽度用百分比自适应：在窄屏自动留出左右边距，避免贴边导致文字被裁切（不再固定 vp 宽度）
const FLOATING_BAR_WIDTH: string = '88%';
const FLOATING_RESERVE: number = BAR_BOTTOM_MARGIN + FLOATING_BAR_HEIGHT;

// 智感握持跟手：底栏水平偏移量（vp，仅折叠屏生效）。左手握持偏左、右手握持偏右、其它居中。
const GRIP_OFFSET: number = 24;

// 仅折叠屏设备启用智感握持跟手：折叠屏单手够不到对侧，跟手偏移更实用；
// 普通直板手机固定居中（deviceType 为 'phone'），不申请权限、不开启监听。
const IS_FOLDABLE: boolean = deviceInfo.deviceType === 'foldable';

// 选中 Tab 粒子爆裂特效总开关（暂时关闭；true 可恢复）。false 时连 Particle 组件都不渲染。
const PARTICLE_ENABLED: boolean = false;

@Entry
@Component
struct Index {
  @State current: number = 0;
  @Provide pageStack: NavPathStack = new NavPathStack();
  // 智感握持：底栏水平偏移（由 motion 感知握持手驱动）
  @State gripOffsetX: number = 0;
  @State showPrivacy: boolean = false; // 首次启动隐私同意遮罩

  // 每个 Tab 项对应的粒子发射器属性（emitRate 动态控制是否爆裂）
  @State emitters: EmitterProperty[][] = [
    [{ index: 0, emitRate: 0, position: { x: 30, y: 30 }, size: { width: 60, height: 60 } }],
    [{ index: 0, emitRate: 0, position: { x: 30, y: 30 }, size: { width: 60, height: 60 } }],
    [{ index: 0, emitRate: 0, position: { x: 30, y: 30 }, size: { width: 60, height: 60 } }],
    [{ index: 0, emitRate: 0, position: { x: 30, y: 30 }, size: { width: 60, height: 60 } }]
  ];

  private readonly tabIcons: Resource[] = [
    $r('sys.symbol.book'),
    $r('sys.symbol.bookmark'),
    $r('sys.symbol.checkmark_circle'),
    $r('sys.symbol.person')
  ];
  private readonly tabLabels: string[] = ['知识库', '速记卡', '题库', '个人中心'];

  // 握持手感知回调（保存引用以便 off 注销）；status 为 motion.HoldingHandStatus 枚举值
  private gripCallback: (status: number) => void = (status: number) => {
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD ||
        status === motion.HoldingHandStatus.BOTH_HANDS_HELD) {
      this.gripOffsetX = -GRIP_OFFSET; // 左手/双手：底栏左移，靠近左手拇指
    } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      this.gripOffsetX = GRIP_OFFSET;  // 右手：底栏右移
    } else {
      this.gripOffsetX = 0;            // 未识别/放桌面：居中
    }
  };

  // 通知/深链启动：若来自今日提醒(target=today)，自动直达备考计划页
  aboutToAppear(): void {
    // 主页 4 个 Tab 均为品牌渐变头部覆盖状态栏，状态栏图标统一用浅色（白）
    applyStatusBar('brand');
    const target: string = AppStorage.get<string>('launchTarget') ?? '';
    if (target === 'today') {
      AppStorage.set('launchTarget', '');
      // 延迟到首帧渲染完成后再压栈，避免在组件初始渲染期间修改 @Provide pageStack 状态
      // （否则会触发 "State variable 'pageStack' has changed during render!" 告警）。
      setTimeout(() => {
        this.pageStack.pushPathByName('StudyPlan', {} as Record<string, Object>);
      }, 0);
    }
    // 仅折叠屏设备启用智感握持跟手；普通手机固定居中，不申请权限、不开启监听
    if (IS_FOLDABLE) {
      this.requestGripPermission();
    }
    // 首次启动展示隐私政策同意；同意状态用 Preferences 持久化，避免每次进入都弹窗
    preferences.getPreferences(getContext(this), 'app_pref').then((p: preferences.Preferences) => {
      if (!p.getSync('privacyAgreed', false)) {
        this.showPrivacy = true;
      }
    }).catch(() => {
      // 读取失败则保守弹窗，待用户同意
      this.showPrivacy = true;
    });
  }

  aboutToDisappear(): void {
    // 注销监听，避免热重载叠加监听器
    try {
      motion.off('holdingHandChanged', this.gripCallback);
    } catch (e) {
      // 忽略
    }
  }

  // 运行时申请 DETECT_GESTURE 权限；授权成功后开启握持监听
  private requestGripPermission(): void {
    const atManager = abilityAccessCtrl.createAtManager();
    const ctx = getContext(this);
    try {
      atManager.requestPermissionsFromUser(ctx, ['ohos.permission.DETECT_GESTURE'])
        .then((result) => {
          if (result.authResults[0] === 0) {
            this.startGripMonitoring();
          }
        })
        .catch(() => {
          // 用户拒授权或申请失败：底栏保持居中，不影响其它功能
        });
    } catch (e) {
      // 上下文未就绪等异常：忽略，底栏保持居中
    }
  }

  // 开启握持手感知（纯事件驱动，无需 start）；设备不支持时静默降级
  private startGripMonitoring(): void {
    try {
      motion.on('holdingHandChanged', this.gripCallback);
    } catch (e) {
      // errCode 801 表示设备不支持该能力，保持居中即可
      console.info('[Index] grip monitoring unavailable, fallback to centered bar');
    }
  }

  // 触发某 Tab 的粒子爆裂：瞬时调高 emitRate，短暂停顿后归零
  private burst(idx: number): void {
    if (!PARTICLE_ENABLED) {
      return;
    }
    const make = (rate: number): EmitterProperty[] => [
      { index: 0, emitRate: rate, position: { x: 30, y: 30 }, size: { width: 60, height: 60 } }
    ];
    this.emitters[idx] = make(320);
    this.emitters = [...this.emitters];
    setTimeout(() => {
      this.emitters[idx] = make(0);
      this.emitters = [...this.emitters];
    }, 170);
  }

  // 点击底栏项切换页面：直接更新 current，Swiper 的 .index(this.current) 随之切换并触发 onChange 爆裂
  private switchTo(idx: number): void {
    this.current = idx;
  }

  // 悬浮胶囊底栏的单个 Tab 项（图标 + 文字上下布局），选中高亮 + 图标回弹缩放
  @Builder tabBarItem(idx: number, icon: Resource, label: string) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        // 选中时的高亮胶囊底（品牌浅色）
        if (this.current === idx) {
          Column()
            .width(38)
            .height(38)
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(19)
            .animation({ curve: SPRING_CURVE, duration: 260 })
        }
        // 图标：选中态品牌蓝 + 轻微回弹缩放反馈
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary')])
          .scale({ x: this.current === idx ? 1.15 : 1.0, y: this.current === idx ? 1.15 : 1.0 })
          .animation({ curve: SPRING_CURVE, duration: 260 })
        // 粒子特效层：选中时由 burst() 触发爆裂（PARTICLE_ENABLED 关闭时不渲染）
        if (PARTICLE_ENABLED) {
          Particle({
            particles: [
              {
                emitter: {
                  particle: {
                    type: ParticleType.POINT,
                    config: { radius: 3 },
                    count: 22,
                    lifetime: 600,
                    lifetimeRange: 120
                  },
                  emitRate: this.emitters[idx][0].emitRate,
                  position: [30, 30],
                  shape: ParticleEmitterShape.CIRCLE
                },
                color: {
                  range: [0x2563EB, 0xF97316],
                  updater: {
                    type: ParticleUpdater.CURVE,
                    config: [
                      { from: 0x2563EB, to: 0xF97316, startMillis: 0, endMillis: 600, curve: Curve.EaseOut }
                    ]
                  }
                },
                opacity: {
                  range: [1.0, 1.0],
                  updater: {
                    type: ParticleUpdater.CURVE,
                    config: [{ from: 1.0, to: 0.0, startMillis: 0, endMillis: 600, curve: Curve.EaseOut }]
                  }
                },
                scale: {
                  range: [0.3, 0.7],
                  updater: {
                    type: ParticleUpdater.CURVE,
                    config: [{ from: 0.3, to: 0.9, startMillis: 320, endMillis: 600, curve: Curve.EaseOut }]
                  }
                },
                acceleration: {
                  speed: { range: [30, 90], updater: { type: ParticleUpdater.RANDOM, config: [1, 100] } },
                  angle: { range: [0, 360] }
                }
              }
            ]
          })
            .width(60)
            .height(60)
            .emitter(this.emitters[idx])
        }
      }
      .width(40)
      .height(40)
      .alignSelf(ItemAlign.Center)

      Text(label)
        .fontSize(FONT.mini)
        .fontWeight(this.current === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.switchTo(idx);
    })
  }

  // 悬浮胶囊底栏（叠加在内容上方，跟随握持手左右平移）
  @Builder floatingTabBar() {
    Row({ space: 0 }) {
      ForEach([0, 1, 2, 3], (idx: number) => {
        this.tabBarItem(idx, this.tabIcons[idx], this.tabLabels[idx]);
      }, (idx: number) => idx.toString())
    }
    .width(FLOATING_BAR_WIDTH)
    .height(FLOATING_BAR_HEIGHT)
    .borderRadius(30)
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
    .translate({ x: this.gripOffsetX })
    .animation({ duration: 320, curve: Curve.EaseInOut })
    .margin({ bottom: this.safeBottom + BAR_BOTTOM_MARGIN })
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  // 订阅字号变化，触发本常驻根组件（Tab 标签等）重渲染
  @StorageProp('fontScale') _fs: number = 1;

  // 路由表：routeName -> NavDestination 组件（参数经 routeMap 的 param 透传）
  // 子页多为浅色背景（BackHeader），进入时状态栏跟随主题；退出回到品牌主页恢复白字。
  // Practice 路由（开始模考）承载的 PracticeView 自身为品牌渐变头部，仍用白字；题库主 Tab 复用真题库列表页。
  @Builder
  private routeMap(name: string, param: Object) {
    if (name === 'Detail') {
      NavDestination() {
        Detail({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Search') {
      NavDestination() {
        SearchPage({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Favorites') {
      NavDestination() {
        Favorites()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'StudyRecord') {
      NavDestination() {
        StudyRecord()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'ExamRecord') {
      NavDestination() {
        ExamRecord()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'StudyPlan') {
      NavDestination() {
        StudyPlan()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Practice') {
      NavDestination() {
        PracticeView({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('brand');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Knowledge') {
      NavDestination() {
        KnowledgeView()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'QuestionBank') {
      NavDestination() {
        QuestionBankView({})
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'MyMark') {
      NavDestination() {
        MyMarkView()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'AudioAnswer') {
      NavDestination() {
        AudioAnswerView({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'VideoAnswer') {
      NavDestination() {
        VideoAnswerView({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('brand');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'VideoReview') {
      NavDestination() {
        VideoReviewView({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('brand');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'AudioReview') {
      NavDestination() {
        AudioReviewView({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Settings') {
      NavDestination() {
        SettingsView()
      }.hideTitleBar(true)
      .onAppear(() => { applyStatusBar('theme'); })
    } else if (name === 'FlashcardCollection') {
      NavDestination() {
        FlashcardCollection()
      }.hideTitleBar(true)
      .onAppear(() => { applyStatusBar('theme'); })
      .onDisAppear(() => { applyStatusBar('brand'); })
    } else if (name === 'TestLab') {
      NavDestination() {
        TestLabView()
      }.hideTitleBar(true)
      .onAppear(() => { applyStatusBar('theme'); })
      .onDisAppear(() => { applyStatusBar('brand'); })
    } else if (name === 'AICaptionDemo') {
      NavDestination() {
        AICaptionDemoView()
      }.hideTitleBar(true)
      .onAppear(() => { applyStatusBar('theme'); })
      .onDisAppear(() => { applyStatusBar('brand'); })
    } else if (name === 'SpeechRecognizerDemo') {
      NavDestination() {
        SpeechRecognizerDemoView()
      }.hideTitleBar(true)
      .onAppear(() => { applyStatusBar('theme'); })
      .onDisAppear(() => { applyStatusBar('brand'); })
    } else if (name === 'LocalKnowledge') {
      NavDestination() {
        LocalKnowledgeView()
      }.hideTitleBar(true)
      .onAppear(() => { applyStatusBar('theme'); })
      .onDisAppear(() => { applyStatusBar('brand'); })
    }
  }

  // 隐私政策同意遮罩（首次启动，拒绝则退出应用）
  @Builder privacyMask() {
    Column() {
      Column() {
        Text('隐私政策与用户协议')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .margin({ bottom: SPACE.md })
        Scroll() {
          Column() {
            Text('我们非常重视您的隐私。使用前请阅读以下说明：')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
            Text('本应用资料本地内置，检索在端侧完成。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
              .margin({ top: SPACE.sm })
            Text('开口自测录音仅用于本地回放与端侧转写。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
              .margin({ top: SPACE.sm })
            Text('开启「AI 智能评测」时，录音与转写文本会经网络发送至第三方语音与大模型服务，用于转写与评分。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
              .margin({ top: SPACE.sm })
            Text('备考提醒通过系统代理提醒能力推送。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
              .margin({ top: SPACE.sm })
            Text('我们不会出售您的个人信息。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
              .margin({ top: SPACE.sm })
            Text('完整条款请点击下方「查看隐私政策」。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(FONT.body + 6)
              .width('100%')
              .margin({ top: SPACE.md })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .flexShrink(1)
        Text('查看隐私政策')
          .fontSize(FONT.body)
          .fontColor($r('app.color.brand'))
          .margin({ top: SPACE.sm, bottom: SPACE.md })
          .onClick(() => this.openPrivacyPolicy())
        Row() {
          Button('不同意并退出')
            .layoutWeight(1)
            .backgroundColor($r('app.color.surface_variant'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.rejectPrivacy())
          Button('同意并继续')
            .layoutWeight(1)
            .margin({ left: SPACE.sm })
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .onClick(() => this.agreePrivacy())
        }
        .width('100%')
      }
      .width('88%')
      .height('80%')
      .padding(SPACE.lg)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.lg)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(999)
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private openPrivacyPolicy(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({ action: 'ohos.want.action.viewData', uri: PRIVACY_POLICY_URL });
    } catch (e) {
      // 无可用浏览器时静默忽略
    }
  }

  private agreePrivacy(): void {
    AppStorage.setOrCreate('privacyAgreed', true);
    // 持久化同意状态，下次进入不再弹窗
    try {
      const p: preferences.Preferences =
        preferences.getPreferencesSync(getContext(this), { name: 'app_pref' });
      p.putSync('privacyAgreed', true);
      p.flush();
    } catch (e) {
      // 持久化失败时内存态仍生效，仅本次生效
    }
    this.showPrivacy = false;
  }

  private rejectPrivacy(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  build() {
    // 根容器：Navigation 路由根 + 悬浮底部导航栏（智感握持跟手）
    Navigation(this.pageStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主内容区：Swiper 横向分页，滑动/点击均可切换，底部预留悬浮栏高度
        Swiper() {
          Column() { CategoryView() }
            .key(this._fs.toString())
            .height('100%')
            .padding({ bottom: FLOATING_RESERVE + this.safeBottom })
          Column() { FlashcardView() }
            .key(this._fs.toString())
            .height('100%')
            .padding({ bottom: FLOATING_RESERVE + this.safeBottom })
          Column() { QuestionBankView({ root: true }) }
            .key(this._fs.toString())
            .height('100%')
            .padding({ bottom: FLOATING_RESERVE + this.safeBottom })
          Column() { ProfileView() }
            .key(this._fs.toString())
            .height('100%')
            .padding({ bottom: FLOATING_RESERVE + this.safeBottom })
        }
        .width('100%')
        .height('100%')
        .index(this.current)
        .indicator(false)
        .loop(false)
        .onChange((idx: number) => {
          this.current = idx;
          this.burst(idx);
        })

        // 悬浮胶囊底栏（叠加在内容上方，跟随握持手左右平移）
        this.floatingTabBar()
        // 首次启动隐私同意遮罩（全屏覆盖，未同意前屏蔽交互）
        if (this.showPrivacy) {
          this.privacyMask()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    }
    .hideTitleBar(true)
    .navDestination(this.routeMap)
    .mode(NavigationMode.Stack)
  }
}

// 预览专用：独立 struct，Previewer 渲染时无需 router/storage 上下文
@Preview
@Component
struct IndexPreview {
  @State current: number = 0;
  @Provide pageStack: NavPathStack = new NavPathStack();
  @StorageProp('safeBottom') safeBottom: number = 24;

  private readonly tabIcons: Resource[] = [
    $r('sys.symbol.book'),
    $r('sys.symbol.bookmark'),
    $r('sys.symbol.checkmark_circle'),
    $r('sys.symbol.person')
  ];
  private readonly tabLabels: string[] = ['知识库', '速记卡', '题库', '个人中心'];

  @Builder previewTabItem(idx: number, icon: Resource, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary')])
      Text(label)
        .fontSize(FONT.mini)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.current = idx;
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper() {
        CategoryView()
        FlashcardView()
        QuestionBankView({ root: true })
        ProfileView()
      }
      .width('100%')
      .height('100%')
      .index(this.current)
      .indicator(false)
      .loop(false)
      .onChange((idx: number) => { this.current = idx; })

      Row({ space: 0 }) {
        ForEach([0, 1, 2, 3], (idx: number) => {
          this.previewTabItem(idx, this.tabIcons[idx], this.tabLabels[idx]);
        }, (idx: number) => idx.toString())
      }
      .width(FLOATING_BAR_WIDTH)
      .height(FLOATING_BAR_HEIGHT)
      .borderRadius(30)
      .backgroundColor($r('app.color.surface'))
      .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
      .margin({ bottom: this.safeBottom + 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

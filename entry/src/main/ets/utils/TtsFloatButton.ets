// TTS 悬浮播控按钮（参考学习强国）
// 三态：收起（小圆可拖拽）→ 迷你（暂停条）→ 展开（完整控制栏）
// 参考学习强国：常驻小圆 FAB（空闲也可见、可拖拽），播放时展开控制栏。
// 支持自由拖拽，根据位置自动切换展开方向（靠左向右展，靠右向左展）
// 定位方案：页面 Stack 用 alignContent: Alignment.BottomStart 把 FAB 锚定在左下角，
//   FAB 自身只靠 translate() 做微调偏移（避免 position()/markAnchor() 的 ArkTS 类型坑；
//   也避免 .alignSelf(Alignment) —— 它的形参类型是 ItemAlign，传 Alignment 会编译报错，见 commit 847a1b1）。
//   坐标模型：translate(x,y) 中 x 右为正、y 下为正；baseX=距左、baseY=距底（从屏幕底部向上的距离）。
//   因锚点已是 BottomStart，按钮默认就贴左下角，【无需在 aboutToAppear 读取屏幕高度】，
//   从而规避了 display 未就绪时高度读到 0、按钮被顶到左上角的历史 bug（见 commit ea1da94）。
import display from '@ohos.display';
import { TtsManager, SPEED_LABELS } from './TtsManager';
import { FONT, RADIUS, SPACE } from './Theme';

// 悬浮按钮展开状态枚举
enum FloatState {
  Collapsed = 0,   // 收起：小圆按钮
  Mini = 1,        // 迷你：紧凑暂停条
  Expanded = 2     // 展开：完整控制面板
}

// 屏幕尺寸（vp 单位）
interface ScreenSize {
  w: number;
  h: number;
}

// 阴影样式（避免 arkts-no-untyped-obj-literals）
interface ShadowStyle {
  radius: number;
  color: ResourceColor;
  offsetX: number;
  offsetY: number;
}

@Component
export struct TtsFloatButton {
  // 全局 TTS 状态（AppStorage 双向绑定）
  @StorageLink('ttsPlaying') @Watch('onPlayingChange') playing: boolean = false;   // 会话进行中（含暂停）——驱动可见性
  @StorageLink('ttsPaused') paused: boolean = false;     // 全局暂停态
  @StorageLink('ttsText') activeText: string = '';      // 当前正在朗读的文本
  @StorageLink('ttsSpeed') speed: number = 1.0;

  // 悬浮按钮自身状态
  @State floatState: FloatState = FloatState.Collapsed;
  @State baseX: number = 16;      // 距左距离（vp）：BottomStart 锚点 + translate
  @State baseY: number = 80;      // 距底距离（vp）：从屏幕底部向上的距离（默认避开采底部操作栏）
  @State dragX: number = 0;       // 拖拽瞬时偏移 X（vp，累计）
  @State dragY: number = 0;       // 拖拽瞬时偏移 Y（vp，累计）

  // 尺寸常量
  private readonly BTN_SIZE: number = 48;
  private readonly PANEL_HEIGHT: number = 52;
  private readonly EXPANDED_WIDTH: number = 280;
  private readonly MINI_WIDTH: number = 160;
  // 底部操作栏预留：底部 Tab 栏约 56vp + UI 规范间隙 24vp = 80vp
  private readonly BOTTOM_RESERVE: number = 80;
  private readonly LEFT_MARGIN: number = 16;

  aboutToAppear(): void {
    // 坐标模型版本迁移：v2 用 BottomStart + baseY(距底)，与旧版 TopStart + posY(距顶) 语义不同，
    // 故首次进入时清掉旧版残留坐标，避免 Y 轴语义错乱导致按钮跑到顶部。
    if (AppStorage.get<string>('ttsFloatVer') !== '2') {
      AppStorage.setOrCreate('ttsFloatVer', '2');
      AppStorage.delete('ttsFloatX');
      AppStorage.delete('ttsFloatY');
    }
    const savedX: number | undefined = AppStorage.get<number>('ttsFloatX');
    const savedY: number | undefined = AppStorage.get<number>('ttsFloatY');
    if (savedX !== undefined && savedY !== undefined) {
      this.baseX = savedX;
      this.baseY = savedY;
    } else {
      // 默认锚定「左下角 + 规范偏移」：距左 LEFT_MARGIN，距底 = Tab 栏预留。
      // 关键：默认落点只由 BottomStart 锚点 + 常量决定，此处【不读屏幕高度】，
      // 因此即便 display 尚未就绪也不会错位（历史 bug 即源于此）。
      // 全屏沉浸式下底部手势区透明可交互；默认落点 baseY=BOTTOM_RESERVE(80vp) 已高于手势区(~34vp)，
      // 故无需额外避让，按钮不会被手势条遮挡。
      this.baseX = this.LEFT_MARGIN;
      this.baseY = this.BOTTOM_RESERVE;
    }
  }

  // 监听播放状态变化：开始播报→自动展开迷你条；会话结束→收起（空闲常驻小圆）
  onPlayingChange(): void {
    if (this.playing) {
      // 开始播报：自动展开到迷你条
      this.floatState = FloatState.Mini;
    } else {
      // 会话结束：收起为常驻小圆
      this.floatState = FloatState.Collapsed;
    }
  }

  // 当前显示的标题文本（截断到指定长度）
  private get displayTitle(): string {
    if (!this.activeText) return '语音播报';
    return this.activeText.length > 30 ? this.activeText.slice(0, 30) + '…' : this.activeText;
  }

  // 进度百分比（0-1）：供底部 Progress 组件使用
  // 用当前句下标 / 总句数估算（CoreSpeechKit TTS 无原生按字/按时间进度回调）
  private get progressPercent(): number {
    if (!this.playing) return 0;
    const total: number = TtsManager.totalSegments;
    if (total <= 0) return 0;
    const current: number = TtsManager.currentSegment;
    return Math.max(0, Math.min(1, current / total));
  }

  // 获取倍速标签文本
  private get speedLabel(): string {
    const speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.5];
    const idx: number = speeds.indexOf(this.speed);
    return idx >= 0 && idx < SPEED_LABELS.length ? SPEED_LABELS[idx] : `${this.speed}x`;
  }

  // 进度时间文本（格式 MM:ss/MM:ss）
  // CoreSpeechKit TTS 无原生进度回调，当前用句子级进度估算；无播放时显示占位符
  private get progressText(): string {
    if (!this.playing) return '--:--/--:--';
    // 从 TtsManager 获取当前句索引和总句数做估算进度
    const current: number = TtsManager.currentSegment;
    const total: number = TtsManager.totalSegments;
    if (total <= 0) return '00:00/--:--';
    // 粗略估算：假设平均每句读 5 秒（后续可接入真实引擎回调优化）
    const elapsedSec: number = Math.round(current * 5);
    const totalSec: number = Math.round(total * 5);
    return `${this.formatTime(elapsedSec)}/${this.formatTime(totalSec)}`;
  }

  // 秒数 → MM:ss 格式
  private formatTime(sec: number): string {
    const m: number = Math.floor(sec / 60);
    const s: number = sec % 60;
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }

  // 当前总偏移量（基准位置 + 拖拽瞬时偏移）
  // 坐标系：BottomStart 锚点（按钮默认贴左下角），translate x 右为正、y 下为正。
  // 因此「距底 baseY」需取负映射到 translate.y（向上 = 减小距底）。
  private get totalX(): number {
    return this.baseX + this.dragX;
  }

  private get totalY(): number {
    return -this.baseY + this.dragY;
  }

  // 点击切换状态（播放态下）
  private onFloatTap(): void {
    if (!this.playing) {
      // 空闲态：尝试重播上一段（若无则无操作）
      if (TtsManager.hasLast) {
        TtsManager.replayLast();
      }
      return;
    }
    if (this.floatState === FloatState.Collapsed) {
      this.floatState = FloatState.Mini;
    } else if (this.floatState === FloatState.Mini) {
      this.floatState = FloatState.Expanded;
    } else {
      this.floatState = FloatState.Collapsed;
    }
  }

  private onPauseToggle(): void {
    if (this.paused) {
      TtsManager.resume();
    } else {
      TtsManager.pause();
    }
  }

  // 「下一个」按钮：跳过当前句，朗读下一句（学习强国 skip forward 行为）
  private onNext(): void {
    TtsManager.next();
  }

  private onClose(): void {
    TtsManager.stop();
    this.floatState = FloatState.Collapsed;
  }

  private onCycleSpeed(): void {
    TtsManager.cycleSpeed();
  }

  // 保存基准位置（注意存的是 baseX/baseY，不是带负号的 totalY）
  private savePosition(): void {
    AppStorage.setOrCreate('ttsFloatX', this.baseX);
    AppStorage.setOrCreate('ttsFloatY', this.baseY);
  }

  // 获取屏幕逻辑尺寸（vp），避免把像素当 vp 用导致边界错乱
  // 注意：此方法依赖窗口已就绪。aboutToAppear 阶段不调用它（避免读到 0），
  // 仅在拖拽结束 clampPosition 里调用——此时窗口必然已就绪。
  private getScreenVp(): ScreenSize {
    try {
      const d = display.getDefaultDisplaySync();
      const scale: number = d.densityPixels > 0 ? d.densityPixels : 1;
      const result: ScreenSize = { w: d.width / scale, h: d.height / scale };
      return result;
    } catch (e) {
      const fallback: ScreenSize = { w: 360, h: 720 };
      return fallback;
    }
  }

  // 拖拽结束：把瞬时偏移并入基准位置，并做边界 clamp（vp 单位）
  private clampPosition(): void {
    this.baseX += this.dragX;
    this.baseY -= this.dragY;   // BottomStart：手指下移(dragY>0) → 距底减小
    this.dragX = 0;
    this.dragY = 0;
    const scr = this.getScreenVp();
    const panelW: number = this.getPanelWidth();
    // 水平：LEFT_MARGIN ~ 屏宽-面板宽（左侧保留规范间隙）
    this.baseX = Math.max(this.LEFT_MARGIN, Math.min(this.baseX, Math.max(this.LEFT_MARGIN, scr.w - panelW)));
    // 垂直（距底）：保底 80vp ~ 屏高-面板高（不允许拖出屏幕上下边界，且最低不低于 Tab 栏 + 间距）
    const minBottom: number = this.BOTTOM_RESERVE;
    const maxBottom: number = scr.h > 0 ? Math.max(minBottom, scr.h - this.PANEL_HEIGHT) : 9999;
    this.baseY = Math.max(minBottom, Math.min(this.baseY, maxBottom));
    this.savePosition();
  }

  // 根据当前状态获取面板宽度
  private getPanelWidth(): number {
    if (this.floatState === FloatState.Expanded) return this.EXPANDED_WIDTH;
    if (this.floatState === FloatState.Mini) return this.MINI_WIDTH;
    return this.BTN_SIZE;
  }

  build() {
    // 始终渲染（空闲也常驻小圆，可拖拽），单根 Column + if/else 分支
    Column() {
      if (!this.playing && this.floatState === FloatState.Collapsed) {
        // 空闲常驻：淡色小圆（可拖拽，点按重播上一段）
        this.buildCollapsedBtn(false)
      } else if (this.floatState === FloatState.Collapsed) {
        // 播放中收起：品牌色小圆
        this.buildCollapsedBtn(true)
      } else if (this.floatState === FloatState.Mini) {
        this.buildMiniBar()
      } else {
        this.buildExpandedPanel()
      }
    }
    .width(this.getPanelWidth())
    .height(this.floatState === FloatState.Collapsed ? this.BTN_SIZE : this.PANEL_HEIGHT)
    // Stack 对齐由页面控制（BottomStart = 左下角锚点），这里只用 translate 微调位置
    .translate({ x: this.totalX, y: this.totalY })    // x 右正、y 下正（baseY 已取负）
    .gesture(
      PanGesture()
        // event.offsetX/offsetY 单位为 vp，与 translate 的 x/y 一致，故拖拽 1:1 跟手，无需按 density 换算
        .onActionUpdate((event: GestureEvent) => {
          this.dragX = event.offsetX;
          this.dragY = event.offsetY;
        })
        .onActionEnd(() => {
          this.clampPosition();
        })
    )
  }

  // ====== 收起态小圆按钮 ======
  @Builder
  buildCollapsedBtn(active: boolean) {
    Column() {
      Text('语')   // 纯汉字，避免 emoji 在部分机型渲染失败（见 commit 8d0ebb7）
        .fontSize(22)
    }
    .width(this.BTN_SIZE)
    .height(this.BTN_SIZE)
    .borderRadius(this.BTN_SIZE / 2)
    .backgroundColor(active ? $r('app.color.brand') : $r('app.color.surface'))
    .shadow(this.collapsedShadow(active))
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onFloatTap())
  }

  // 收起态阴影（Builder 内不能声明 const，故抽为方法）
  private collapsedShadow(active: boolean): ShadowStyle {
    return active
      ? { radius: 8, color: '#30000000', offsetX: 0, offsetY: 2 }
      : { radius: 4, color: '#15000000', offsetX: 0, offsetY: 1 };
  }

  // ====== 迷你控制条 ======
  @Builder
  buildMiniBar() {
    Row() {
      Button() {
      Text(this.paused ? '播' : '停')
        .fontSize(18)
        .fontColor(Color.White)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.brand'))
      .borderRadius(20)
      .onClick(() => this.onPauseToggle())

      Text(this.displayTitle)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: SPACE.sm })
        .onClick(() => { this.floatState = FloatState.Expanded; })

      Button() {
        Text('×')
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(32)
      .height(32)
      .backgroundColor($r('app.color.transparent'))
      .borderRadius(16)
      .onClick(() => this.onClose())
    }
    .width(this.MINI_WIDTH)
    .height(this.PANEL_HEIGHT)
    .padding({ left: SPACE.sm, right: SPACE.xs })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .shadow(this.miniShadow)
  }

  // 迷你条阴影样式
  private get miniShadow(): ShadowStyle {
    return { radius: 12, color: '#25000000', offsetX: 0, offsetY: 4 };
  }

  // ====== 展开完整控制栏（参考学习强国：单行横条 + 底部红色进度） ======
  // 布局：主行 [标题(截断)...] [进度] [⏯toggle] [⏭next] [×]
  //       底部 [─────────Progress 红色填充────────]
  // 按钮用纯文本而非 SymbolGlyph：部分 sys.symbol（如 forward）在 API 20 的符号表里不存在，
  // 会导致编译期 Unknown resource name 错误，纯文本无此风险且更可控。
  @Builder
  buildExpandedPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主行：标题 + 进度 + 三个按钮
      Row() {
        // 左侧：标题（可截断）
        Text(this.displayTitle)
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.text_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 中间：进度时间（格式 00:08/03:34）
        Text(this.progressText)
          .fontSize(FONT.mini)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: SPACE.sm, right: SPACE.sm })

        // 播放/暂停 toggle（纯文字：播↔停）
        Button() {
          Text(this.paused ? '播' : '停')
            .fontSize(16)
            .fontColor(Color.White)
        }
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.brand'))
        .borderRadius(18)
        .onClick(() => this.onPauseToggle())

        // 下一个：跳过当前句，朗读下一句（学习强国 skip forward）
        Button() {
          Text('下')
            .fontSize(16)
            .fontColor($r('app.color.text_title'))
        }
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.transparent'))
        .borderRadius(18)
        .margin({ left: SPACE.xs })
        .onClick(() => this.onNext())

        // 关闭按钮
        Button() {
          Text('\u00D7')  // Unicode 乘号（×），不用 emoji
            .fontSize(18)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.transparent'))
        .borderRadius(16)
        .margin({ left: SPACE.xs })
        .onClick(() => this.onClose())
      }
      .width('100%')
      .height(this.PANEL_HEIGHT)
      .padding({ left: SPACE.md, right: SPACE.sm, bottom: 6 })  // 底部预留 6vp 给进度条
      .alignItems(VerticalAlign.Center)

      // 底部进度条（学习强国样式：红色填充 + 半透明灰底）
      Progress({ value: this.progressPercent * 100, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(2)
        .color($r('app.color.danger'))
        .backgroundColor('#22000000')
    }
    .width(this.EXPANDED_WIDTH)
    .height(this.PANEL_HEIGHT)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .shadow(this.expandedShadow)
  }

  // 展开面板阴影样式
  private get expandedShadow(): ShadowStyle {
    return { radius: 16, color: '#30000000', offsetX: 0, offsetY: 6 };
  }
}

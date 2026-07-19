// TTS 悬浮播控按钮（参考学习强国）
// 三态：收起（小圆可拖拽）→ 迷你（暂停条）→ 展开（完整控制栏）
// 参考学习强国：常驻小圆 FAB（空闲也可见、可拖拽），播放时展开控制栏。
// 支持自由拖拽，根据位置自动切换展开方向（靠左向右展，靠右向左展）
// 定位方案：用 translate() 偏移（避免 position()/markAnchor() 的 ArkTS 类型检查坑）
//   坐标模型：Stack 用 Alignment.TopStart，translate(x,y) 中 x/y 均为 vp（下/右为正），
//   故默认位置为「距顶 posY、距左 posX」，拖拽直观。
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
  @State posX: number = 16;       // 距左距离（vp）
  @State posY: number = 600;      // 距顶距离（vp）
  @State dragX: number = 0;       // 拖拽偏移 X（vp，累计）
  @State dragY: number = 0;       // 拖拽偏移 Y（vp，累计）

  // 尺寸常量
  private readonly BTN_SIZE: number = 48;
  private readonly PANEL_HEIGHT: number = 52;
  private readonly EXPANDED_WIDTH: number = 280;
  private readonly MINI_WIDTH: number = 160;

  aboutToAppear(): void {
    const savedX: number | undefined = AppStorage.get<number>('ttsFloatX');
    const savedY: number | undefined = AppStorage.get<number>('ttsFloatY');
    if (savedX !== undefined && savedY !== undefined) {
      this.posX = savedX;
      this.posY = savedY;
    } else {
      // 默认放在左下区域（距顶 = 屏高 - 200）
      const s = this.getScreenVp();
      this.posX = 16;
      this.posY = Math.max(0, s.h - 200);
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

  // 获取倍速标签文本
  private get speedLabel(): string {
    const speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.5];
    const idx: number = speeds.indexOf(this.speed);
    return idx >= 0 && idx < SPEED_LABELS.length ? SPEED_LABELS[idx] : `${this.speed}x`;
  }

  // 当前总偏移量（位置+拖拽）
  private get totalX(): number {
    return this.posX + this.dragX;
  }

  private get totalY(): number {
    return this.posY + this.dragY;
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

  private onClose(): void {
    TtsManager.stop();
    this.floatState = FloatState.Collapsed;
  }

  private onCycleSpeed(): void {
    TtsManager.cycleSpeed();
  }

  // 保存位置
  private savePosition(): void {
    AppStorage.setOrCreate('ttsFloatX', this.totalX);
    AppStorage.setOrCreate('ttsFloatY', this.totalY);
  }

  // 获取屏幕逻辑尺寸（vp），避免把像素当 vp 用导致边界错乱
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

  // 拖拽结束：归位+边界clamp（vp 单位）
  private clampPosition(): void {
    this.posX += this.dragX;
    this.posY += this.dragY;
    this.dragX = 0;
    this.dragY = 0;
    const scr = this.getScreenVp();
    const panelW: number = this.getPanelWidth();
    // 水平：0 ~ 屏宽-面板宽
    this.posX = Math.max(0, Math.min(this.posX, scr.w - panelW));
    // 垂直：0 ~ 屏高-面板高-底部预留
    this.posY = Math.max(0, Math.min(this.posY, scr.h - this.PANEL_HEIGHT - 120));
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
    .translate({ x: this.totalX, y: this.totalY })
    .gesture(
      PanGesture()
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
      Text('🎧')
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
        Text(this.paused ? '▶' : '⏸')
          .fontSize(18)
          .fontColor($r('app.color.on_primary'))
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

  // ====== 展开完整控制面板 ======
  @Builder
  buildExpandedPanel() {
    Column() {
      // 第一行：标题 + 关闭
      Row() {
        Text(this.displayTitle)
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.text_title'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('×')
          .fontSize(20)
          .fontColor($r('app.color.text_tertiary'))
          .padding(SPACE.xs)
          .onClick(() => this.onClose())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 第二行：控制按钮组
      Row() {
        // 倍速
        Column() {
          Text(this.speedLabel)
            .fontSize(FONT.mini)
            .fontColor($r('app.color.brand'))
          Text('倍速')
            .fontSize(FONT.mini)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ left: SPACE.sm, right: SPACE.sm })
        .onClick(() => this.onCycleSpeed())

        Text('|').fontColor($r('app.color.divider')).margin({ left: SPACE.xs, right: SPACE.xs })

        // 上一段（预留）
        Button() {
          Text('⏮').fontSize(18).fontColor($r('app.color.text_title'))
        }
        .width(40).height(40)
        .backgroundColor($r('app.color.transparent')).borderRadius(20)
        .opacity(0.5)

        // 暂停/继续（大按钮居中）
        Button() {
          Text(this.paused ? '▶' : '⏸')
            .fontSize(24)
            .fontColor($r('app.color.on_primary'))
        }
        .width(52).height(52)
        .backgroundColor($r('app.color.brand')).borderRadius(26)
        .margin({ left: SPACE.sm, right: SPACE.sm })
        .onClick(() => this.onPauseToggle())

        // 下一段（预留）
        Button() {
          Text('⏭').fontSize(18).fontColor($r('app.color.text_title'))
        }
        .width(40).height(40)
        .backgroundColor($r('app.color.transparent')).borderRadius(20)
        .opacity(0.5)

        Text('|').fontColor($r('app.color.divider')).margin({ left: SPACE.xs, right: SPACE.xs })

        // 收起
        Column() {
          Text('▼').fontSize(14).fontColor($r('app.color.text_secondary'))
          Text('收起').fontSize(FONT.mini).fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ left: SPACE.sm, right: SPACE.sm })
        .onClick(() => { this.floatState = FloatState.Collapsed; })
      }
      .width('100%').height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ top: SPACE.xs })
    }
    .width(this.EXPANDED_WIDTH)
    .padding({ top: SPACE.sm, bottom: SPACE.sm, left: SPACE.md, right: SPACE.md })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .shadow(this.expandedShadow)
  }

  // 展开面板阴影样式
  private get expandedShadow(): ShadowStyle {
    return { radius: 16, color: '#30000000', offsetX: 0, offsetY: 6 };
  }
}

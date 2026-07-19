// TTS 悬浮播控按钮（参考学习强国）
// 三态：收起（小圆可拖拽）→ 迷你（暂停条）→ 展开（完整控制栏）
// 支持自由拖拽，根据位置自动切换展开方向（靠左向右展，靠右向左展）
import { display } from '@ohos.display';
import { TtsManager, SPEED_LABELS } from './TtsManager';
import { FONT, RADIUS, SPACE } from './Theme';

// 悬浮按钮展开状态枚举
enum FloatState {
  Collapsed = 0,   // 收起：小圆按钮
  Mini = 1,        // 迷你：紧凑暂停条
  Expanded = 2     // 展开：完整控制面板
}

@Component
export struct TtsFloatButton {
  // 全局 TTS 状态（AppStorage 双向绑定）
  @StorageLink('ttsPlaying') playing: boolean = false;
  @StorageLink('ttsPaused') paused: boolean = false;
  @StorageLink('ttsText') activeText: string = '';
  @StorageLink('ttsSpeed') speed: number = 1.0;

  // 悬浮按钮自身状态
  @State floatState: FloatState = FloatState.Collapsed;
  @State posX: number = 16;       // 按钮 X 坐标（默认左下角上方）
  @State posY: number = 0;         // 按钮 Y 坐标（动态计算距底）
  @State dragX: number = 0;        // 拖拽偏移 X
  @State dragY: number = 0;        // 拖拽偏移 Y
  @State showSpeedPanel: boolean = false;  // 是否显示倍速选择面板

  // 尺寸常量
  private readonly BTN_SIZE: number = 48;   // 收起态圆形尺寸
  private readonly PANEL_HEIGHT: number = 52;  // 控制面板高度
  private readonly EXPANDED_WIDTH: number = 280; // 展开面板宽度
  private readonly MINI_WIDTH: number = 160;      // 迷你条宽度

  aboutToAppear(): void {
    // 从 AppStorage 恢复上一次位置（如有）；默认左下角上方
    const savedX: number | undefined = AppStorage.get<number>('ttsFloatX');
    const savedY: number | undefined = AppStorage.get<number>('ttsFloatY');
    if (savedX !== undefined) this.posX = savedX;
    if (savedY !== undefined) this.posY = savedY;
  }

  // 判断当前按钮在屏幕哪半边（决定展开方向）
  private get isOnLeftSide(): boolean {
    return this.posX + this.dragX < display.getDefaultDisplaySync().width / 2;
  }

  // 获取当前显示的标题文本（截断到指定长度）
  private get displayTitle(): string {
    if (!this.activeText) return '语音播报';
    // 取前 30 个字符作为短标题
    return this.activeText.length > 30 ? this.activeText.slice(0, 30) + '…' : this.activeText;
  }

  // 获取倍速标签文本
  private get speedLabel(): string {
    const idx: number = [0.5, 0.75, 1.0, 1.25, 1.5].indexOf(this.speed);
    return idx >= 0 && idx < SPEED_LABELS.length ? SPEED_LABELS[idx] : `${this.speed}x`;
  }

  // 点击收起按钮 → 根据播放状态决定行为
  private onFloatTap(): void {
    if (!this.playing) {
      // 未播放时点击不展开（或可以展开提示"暂无播放内容"）
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

  // 暂停/继续切换
  private onPauseToggle(): void {
    if (this.paused) {
      TtsManager.resume();
    } else {
      TtsManager.pause();
    }
  }

  // 关闭/停止
  private onClose(): void {
    TtsManager.stop();
    this.floatState = FloatState.Collapsed;
    this.showSpeedPanel = false;
  }

  // 倍速切换
  private onCycleSpeed(): void {
    TtsManager.cycleSpeed();
  }

  // 保存位置到 AppStorage（跨页面导航保持位置）
  private savePosition(): void {
    AppStorage.setOrCreate('ttsFloatX', this.posX + this.dragX);
    AppStorage.setOrCreate('ttsFloatY', this.posY + this.dragY);
  }

  build() {
    // 未播放且非强制展示时不渲染（或仅渲染一个极淡的小圆）
    if (!this.playing && this.floatState === FloatState.Collapsed) {
      // 收起态未播放：显示一个小淡色耳机图标作为入口
      Stack() {
        this.buildCollapsedBtn(false)
      }
      .width(this.BTN_SIZE)
      .height(this.BTN_SIZE)
      .position({ x: this.posX + this.dragX, y: this.posY + this.dragY })
      .markAnchor({ cx: 0, cy: 0 })
      .gesture(
        PanGesture()
          .onActionUpdate((event: GestureEvent) => {
            this.dragX = event.offsetX;
            this.dragY = event.offsetY;
          })
          .onActionEnd(() => {
            this.posX += this.dragX;
            this.posY += this.dragY;
            this.dragX = 0;
            this.dragY = 0;
            // 边界限制
            const dw: number = display.getDefaultDisplaySync().width;
            const dh: number = display.getDefaultDisplaySync().height;
            this.posX = Math.max(0, Math.min(this.posX, dw - this.BTN_SIZE));
            this.posY = Math.max(0, Math.min(this.posY, dh - this.BTN_SIZE - 120)); // 避开底部 Tab
            this.savePosition();
          })
      )
      .onClick(() => {
        // 未播放时可点击提示用户先开始朗读
      })
      .visibility(Visibility.Visible)
      return;
    }

    // 播放中或已展开：渲染对应状态
    Stack() {
      if (this.floatState === FloatState.Collapsed) {
        this.buildCollapsedBtn(true)
      } else if (this.floatState === FloatState.Mini) {
        this.buildMiniBar()
      } else {
        this.buildExpandedPanel()
      }
    }
    .width(this.floatState === FloatState.Expanded ? this.EXPANDED_WIDTH :
           this.floatState === FloatState.Mini ? this.MINI_WIDTH : this.BTN_SIZE)
    .height(this.PANEL_HEIGHT)
    .position({ x: this.posX + this.dragX, y: this.posY + this.dragY })
    .markAnchor({ cx: 0, cy: 0 })
    .gesture(
      PanGesture()
        .onActionUpdate((event: GestureEvent) => {
          this.dragX = event.offsetX;
          this.dragY = event.offsetY;
        })
        .onActionEnd(() => {
          this.posX += this.dragX;
          this.posY += this.dragY;
          this.dragX = 0;
          this.dragY = 0;
          // 边界限制
          const dw: number = display.getDefaultDisplaySync().width;
          const dh: number = display.getDefaultDisplaySync().height;
          const panelW: number = this.floatState === FloatState.Expanded ? this.EXPANDED_WIDTH :
                         this.floatState === FloatState.Mini ? this.MINI_WIDTH : this.BTN_SIZE;
          this.posX = Math.max(0, Math.min(this.posX, dw - panelW));
          this.posY = Math.max(0, Math.min(this.posY, dh - this.PANEL_HEIGHT - 120)); // 避开底部 Tab
          this.savePosition();
        })
    )
  }

  // ====== 子 Builder：收起态小圆按钮 ======
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
    .shadow(active ? { radius: 8, color: '#30000000', offsetX: 0, offsetY: 2 } : { radius: 4, color: '#15000000', offsetX: 0, offsetY: 1 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onFloatTap())
  }

  // ====== 子 Builder：迷你控制条 ======
  @Builder
  buildMiniBar() {
    Row() {
      // 暂停/继续按钮
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

      // 标题文字（截断）
      Text(this.displayTitle)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: SPACE.sm })
        .onClick(() => {
          this.floatState = FloatState.Expanded;
        })

      // 关闭
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
    .shadow({ radius: 12, color: '#25000000', offsetX: 0, offsetY: 4 })
  }

  // ====== 子 Builder：完整控制面板 ======
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

        // 分隔线
        Text('|').fontColor($r('app.color.divider')).margin({ left: SPACE.xs, right: SPACE.xs })

        // 上一段（预留：切到上一个朗读内容）
        Button() {
          Text('⏮')
            .fontSize(18)
            .fontColor($r('app.color.text_title'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.transparent'))
        .borderRadius(20)
        .opacity(0.5) // 暂无"上一段"能力，置灰

        // 暂停/继续（大按钮居中）
        Button() {
          Text(this.paused ? '▶' : '⏸')
            .fontSize(24)
            .fontColor($r('app.color.on_primary'))
        }
        .width(52)
        .height(52)
        .backgroundColor($r('app.color.brand'))
        .borderRadius(26)
        .margin({ left: SPACE.sm, right: SPACE.sm })
        .onClick(() => this.onPauseToggle())

        // 下一段（预留）
        Button() {
          Text('⏭')
            .fontSize(18)
            .fontColor($r('app.color.text_title'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.transparent'))
        .borderRadius(20)
        .opacity(0.5)

        // 分隔线
        Text('|').fontColor($r('app.color.divider')).margin({ left: SPACE.xs, right: SPACE.xs })

        // 收起
        Column() {
          Text('▼')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text('收起')
            .fontSize(FONT.mini)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ left: SPACE.sm, right: SPACE.sm })
        .onClick(() => {
          this.floatState = FloatState.Collapsed;
        })
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ top: SPACE.xs })
    }
    .width(this.EXPANDED_WIDTH)
    .padding({ top: SPACE.sm, bottom: SPACE.sm, left: SPACE.md, right: SPACE.md })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .shadow({ radius: 16, color: '#30000000', offsetX: 0, offsetY: 6 })
  }
}

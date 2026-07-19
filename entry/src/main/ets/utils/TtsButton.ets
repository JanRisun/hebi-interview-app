// 语音播报按钮（可复用）
// 通过 AppStorage 全局同步播放态：多个按钮共享同一个 TTS 引擎，
// 任意按钮点击都会正确反映「正在播放/暂停」状态。
// V2：支持暂停/继续状态区分（与悬浮按钮联动）
// 说明：用 Row + Text 自定义药丸按钮，避免 Button(text) 在部分场景下塌成圆块无字。
import { TtsManager } from './TtsManager';
import { FONT, RADIUS, SPACE } from './Theme';

@Component
export struct TtsButton {
  @Prop text: string = '';                       // 要朗读的内容
  @Prop label: string = '🔊 朗读';                // 未播放时的按钮文案
  @StorageLink('ttsPlaying') playing: boolean = false;   // 全局播放态（会话进行中，含暂停）
  @StorageLink('ttsPaused') paused: boolean = false;     // 全局暂停态
  @StorageLink('ttsText') activeText: string = '';       // 当前正在朗读的文本

  // 判断当前文本是否是"活跃朗读目标"
  private get isActive(): boolean {
    return this.playing && this.activeText === this.text;
  }

  // 根据状态决定按钮文案
  private get btnLabel(): string {
    if (!this.isActive) {
      return this.label;          // 未播或播别的 → 原始标签
    }
    if (this.paused) {
      return '▶ 继续';            // 暂停中 → 继续
    }
    return '⏸ 暂停';              // 播放中 → 暂停
  }

  build() {
    // 用 Row + Text 自定义药丸按钮，保证始终可见、有文字
    Row() {
      Text(this.btnLabel)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.on_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(36)
    .padding({ left: SPACE.md, right: SPACE.md })
    .backgroundColor(
      this.isActive
        ? (this.paused ? $r('app.color.warning') : $r('app.color.danger'))
        : $r('app.color.brand')
    )
    .borderRadius(RADIUS.pill)
    .onClick(() => {
      // toggle 作用在全局单例引擎上：无论哪个页面的按钮点击，都会同步驱动 AppStorage 状态，
      // 因此本按钮与悬浮按钮、其他页面按钮的播放/暂停态始终一致。
      TtsManager.toggle(this.text);
    })
  }
}

// 语音播报按钮（可复用）
// 通过 AppStorage 全局同步播放态：多个按钮共享同一个 TTS 引擎，
// 任意按钮点击都会正确反映「正在播放」状态，避免多个按钮同时显示「停止」。
import { TtsManager } from '../utils/TtsManager';
import { FONT, RADIUS, SPACE } from '../utils/Theme';

@Component
export struct TtsButton {
  @Prop text: string = '';                       // 要朗读的内容
  @Prop label: string = '🔊 朗读';                // 未播放时的按钮文案
  @StorageLink('ttsPlaying') playing: boolean = false;  // 全局播放态
  @StorageLink('ttsText') activeText: string = '';   // 当前正在朗读的文本

  build() {
    Button() {
      Text(this.playing && this.activeText === this.text ? '⏹ 停止' : this.label)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.on_primary'))
    }
    .height(36)
    .padding({ left: SPACE.md, right: SPACE.md })
    .backgroundColor(
      this.playing && this.activeText === this.text
        ? $r('app.color.danger')
        : $r('app.color.brand')
    )
    .borderRadius(RADIUS.pill)
    .enabled(this.text.trim().length > 0)
    .onClick(() => {
      TtsManager.toggle(this.text);
    })
  }
}

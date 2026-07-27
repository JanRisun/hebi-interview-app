// 测试功能聚合页：个人中心「测试功能」入口进入，集中放置各类待验证的实验性能力，
// 便于快速调试与演示。当前包含：AI 实时字幕、语音识别（麦克风实时转写）。
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile } from '../utils/Ui';
import { BackHeader } from '../utils/BackHeader';

@Entry
@Component
export struct TestLabView {
  @Consume pageStack: NavPathStack;
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  // 订阅字号变化，触发本页重渲染（FONT getter 实时读取 AppStorage('fontScale')）
  @StorageProp('fontScale') _fs: number = 1;

  private onAICaption(): void {
    this.pageStack.pushPathByName('AICaptionDemo', {} as Record<string, Object>);
  }

  private onRecognizer(): void {
    this.pageStack.pushPathByName('SpeechRecognizerDemo', {} as Record<string, Object>);
  }

  // 通用入口行：emoji 图标块 + 标题 + 副标题 + 箭头
  @Builder entryRow(emoji: string, bg: Resource, fg: Resource, title: string, sub: string, cb: () => void) {
    Row() {
      IconTile({ emoji: emoji, bg: bg, fg: fg, dim: 42 })
        .margin({ right: SPACE.md })
      Column() {
        Text(title)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(sub)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(FONT.title)
        .fontColor($r('app.color.text_arrow'))
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .margin({ bottom: SPACE.sm })
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
    .onClick(cb)
  }

  build() {
    Column() {
      BackHeader({ title: '测试功能', showAction: false })

      Column() {
        Text('以下为实验性 / 待验证能力，便于快速调试演示。')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: SPACE.sm })
      }
      .width('100%')
      .padding({ left: SPACE.md, right: SPACE.md })

      Scroll() {
        Column() {
          this.entryRow('💬', $r('app.color.accent_soft'), $r('app.color.accent'), 'AI 实时字幕',
            '对麦克风说话，实时显示识别文字', () => this.onAICaption())
          this.entryRow('🎙️', $r('app.color.brand_light'), $r('app.color.brand'), '语音识别',
            '麦克风实时语音转文字（SpeechRecognizer）', () => this.onRecognizer())
        }
        .width('100%')
        .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: this.safeBottom + SPACE.lg })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop })
  }
}

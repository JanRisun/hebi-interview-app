// 速记卡 Tab（百词斩式翻转卡）：左滑下一个、右滑进入我的收藏
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Section } from '../model/Types';
import { FONT, RADIUS, SPACE } from '../utils/Theme';
import { TtsButton } from '../utils/TtsButton';

interface Card {
  title: string;
  body: string;
}

@Component
export struct FlashcardView {
  @State cards: Card[] = [];
  @State idx: number = 0;
  @State flipped: boolean = false;   // 翻转状态：false=正面(要点) true=背面(详解)

  aboutToAppear(): void {
    DataStore.load(getContext(this) as common.UIAbilityContext).then(() => {
      const d = DataStore.data;
      const list: Card[] = [];
      d.articles
        .filter((a) => a.category === '考情' || a.category === '题型方法')
        .forEach((a) => {
          a.sections.forEach((s: Section) => {
            if (s.body.trim().length > 10) {
              list.push({ title: a.title + (s.heading ? ' · ' + s.heading : ''), body: s.body });
            }
          });
        });
      this.cards = list;
    });
  }

  // 切换卡片时复位翻转
  private go(delta: number): void {
    const next: number = this.idx + delta;
    if (next < 0 || next >= this.cards.length) return;
    this.idx = next;
    this.flipped = false;
  }

  private toggleFlip(): void {
    this.flipped = !this.flipped;
  }

  // 左滑下一个；右滑进收藏
  private onSwipe(angle: number): void {
    if (angle < 0) {
      this.go(1);
    } else {
      router.pushUrl({ url: 'pages/Favorites' });
    }
  }

  build() {
    Column() {
      // 顶部标题 + 进度
      Row() {
        Text('速记卡')
          .fontSize(FONT.display)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        if (this.cards.length > 0) {
          Text(`  ${this.idx + 1} / ${this.cards.length}`)
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
      }
      .width('92%')
      .margin({ top: SPACE.lg, bottom: SPACE.md })

      if (this.cards.length === 0) {
        Text('加载中…')
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.text_secondary'))
          .margin(SPACE.xl)
      } else {
        // 百词斩式：大卡片居中，点击翻转；左右滑切换/进收藏
        Stack() {
          // 正面：知识点要点
          Column() {
            Text('要点')
              .fontSize(FONT.caption)
              .fontColor($r('app.color.brand'))
              .margin({ bottom: SPACE.md })
            Text(this.cards[this.idx].title)
              .fontSize(FONT.display)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(30)
              .textAlign(TextAlign.Center)
            Text('👆 点击卡片翻转看详解')
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 20 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding(20)
          .visibility(this.flipped ? Visibility.Hidden : Visibility.Visible)
          .rotate({ x: 0, y: 1, angle: this.flipped ? -180 : 0 })
          .animation({ duration: 280, curve: Curve.Ease })

          // 背面：详解内容（可滚动）
          Scroll() {
            Column() {
              Text('详解')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.brand'))
                .margin({ bottom: SPACE.sm })
              Text(this.cards[this.idx].body)
                .fontSize(FONT.body)
                .fontColor($r('app.color.text_body'))
                .lineHeight(24)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(20)
          }
          .width('100%')
          .height('100%')
          .visibility(this.flipped ? Visibility.Visible : Visibility.Hidden)
          .rotate({ x: 0, y: 1, angle: this.flipped ? 0 : 180 })
          .animation({ duration: 280, curve: Curve.Ease })
        }
        .width('88%')
        .height(360)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.lg)
        .shadow({ radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 })
        .onClick(() => this.toggleFlip())
        .gesture(
          SwipeGesture({ direction: SwipeDirection.Horizontal, fingers: 1 })
            .onAction((event) => {
              this.onSwipe(event.angle);
            })
        )

        // 底部操作
        Row({ space: 12 }) {
          Button('上一张')
            .fontSize(FONT.bodySm)
            .height(42)
            .layoutWeight(1)
            .backgroundColor($r('app.color.btn_neutral_bg'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .enabled(this.idx > 0)
            .onClick(() => this.go(-1))
          Button(this.flipped ? '看要点' : '翻转')
            .fontSize(FONT.bodySm)
            .height(42)
            .layoutWeight(1)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .onClick(() => this.toggleFlip())
          Button('下一张')
            .fontSize(FONT.bodySm)
            .height(42)
            .layoutWeight(1)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .enabled(this.idx < this.cards.length - 1)
            .onClick(() => this.go(1))
        }
        .width('88%')
        .margin({ top: 20 })

        // 语音播报：朗读当前可见面（正面要点 / 背面详解）
        Row({ space: 12 }) {
          TtsButton({
            text: this.flipped ? this.cards[this.idx].body : this.cards[this.idx].title,
            label: '🔊 朗读当前面'
          })
        }
        .width('88%')
        .margin({ top: 12 })

        Text('提示：像百词斩一样先凭记忆回想，再翻转核对；左滑下一张，右滑进收藏')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 14 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

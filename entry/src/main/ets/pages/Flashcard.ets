// 速记卡 Tab（百词斩式翻转卡）：左滑下一个、右滑进入我的收藏
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Section } from '../model/Types';

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
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14385c')
        if (this.cards.length > 0) {
          Text(`  ${this.idx + 1} / ${this.cards.length}`)
            .fontSize(14)
            .fontColor('#888')
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
      }
      .width('92%')
      .margin({ top: 16, bottom: 12 })

      if (this.cards.length === 0) {
        Text('加载中…')
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else {
        // 百词斩式：大卡片居中，点击翻转；左右滑切换/进收藏
        Stack() {
          // 正面：知识点要点
          Column() {
            Text('要点')
              .fontSize(12)
              .fontColor('#185FA5')
              .margin({ bottom: 12 })
            Text(this.cards[this.idx].title)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1f2d3d')
              .lineHeight(30)
              .textAlign(TextAlign.Center)
            Text('👆 点击卡片翻转看详解')
              .fontSize(13)
              .fontColor('#aaa')
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
                .fontSize(12)
                .fontColor('#185FA5')
                .margin({ bottom: 10 })
              Text(this.cards[this.idx].body)
                .fontSize(15)
                .fontColor('#2c2c2a')
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
        .backgroundColor('#FFFFFF')
        .borderRadius(18)
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
            .fontSize(14)
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#3a3a3a')
            .fontColor('#FFFFFF')
            .borderRadius(21)
            .enabled(this.idx > 0)
            .onClick(() => this.go(-1))
          Button(this.flipped ? '看要点' : '翻转')
            .fontSize(14)
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#185FA5')
            .fontColor('#FFFFFF')
            .borderRadius(21)
            .onClick(() => this.toggleFlip())
          Button('下一张')
            .fontSize(14)
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#14385c')
            .fontColor('#FFFFFF')
            .borderRadius(21)
            .enabled(this.idx < this.cards.length - 1)
            .onClick(() => this.go(1))
        }
        .width('88%')
        .margin({ top: 20 })

        Text('提示：像百词斩一样先凭记忆回想，再翻转核对；左滑下一张，右滑进收藏')
          .fontSize(12)
          .fontColor('#999')
          .margin({ top: 14 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

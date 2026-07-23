// 速记卡 Tab（百词斩式翻转卡）：左滑下一个、右滑进入我的收藏
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Section } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { ReaderIcon } from '../utils/SpeechReader';
import { PageHero, PageHeader, EmptyState, IconTile, ProgressRing } from '../utils/Ui';

interface Card {
  title: string;
  body: string;
}

@Component
export struct FlashcardView {
  @State cards: Card[] = [];
  @State idx: number = 0;
  @State flipped: boolean = false;   // 翻转状态：false=正面(要点) true=背面(详解)
  @Consume pageStack: NavPathStack;

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
      this.pageStack.pushPathByName('Favorites', {} as Record<string, Object>);
    }
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    // 朗读改用系统朗读控件 TextReader（自带悬浮播控面板），页面内不再自绘悬浮按钮
    Column() {
      // 品牌头部
      PageHeader({ title: '速记卡' })

        if (this.cards.length === 0) {
          EmptyState({ emoji: '⏳', text: '加载中…' })
        } else {
          // 进度行：当前面标签 + 环形进度 + 计数
          Row() {
            Text(this.flipped ? '详解' : '要点')
              .fontSize(FONT.title)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.brand'))
              .layoutWeight(1)
            ProgressRing({ value: this.idx + 1, total: this.cards.length, dim: 38, color: $r('app.color.brand') })
            Text(`${this.idx + 1}/${this.cards.length}`)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: SPACE.sm })
          }
          .width('88%')
          .margin({ top: SPACE.md, bottom: SPACE.sm })

          // 百词斩式：大卡片居中，点击翻转；左右滑切换/进收藏
          Stack() {
            // 正面：知识点要点（渐变底 + 图标）
            Column() {
              IconTile({ emoji: '💡', bg: $r('app.color.on_primary'), fg: $r('app.color.brand'), dim: 52 })
                .margin({ bottom: SPACE.md })
              Text(this.cards[this.idx].title)
                .fontSize(FONT.display)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .lineHeight(30)
                .textAlign(TextAlign.Center)
              Text('点击卡片翻转看详解')
                .fontSize(FONT.bodySm)
                .fontColor($r('app.color.text_hint'))
                .margin({ top: 20 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .padding(20)
            .linearGradient({ angle: 135, colors: [[$r('app.color.brand_light'), 0], [$r('app.color.surface'), 1]] })
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
            .backgroundColor($r('app.color.surface'))
            .visibility(this.flipped ? Visibility.Visible : Visibility.Hidden)
            .rotate({ x: 0, y: 1, angle: this.flipped ? 0 : 180 })
            .animation({ duration: 280, curve: Curve.Ease })
          }
          .width('88%')
          .height(360)
          .borderRadius(RADIUS.lg)
          .shadow({ radius: 16, color: $r('app.color.card_stroke'), offsetX: 0, offsetY: 6 })
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
          // id 含 idx 与翻面状态，切卡/翻面即视为新的朗读目标
          ReaderIcon({
            readId: 'card:' + this.idx + (this.flipped ? ':b' : ':f'),
            title: this.cards[this.idx].title,
            text: this.flipped ? this.cards[this.idx].body : this.cards[this.idx].title,
            label: '朗读当前面'
          })
          .margin({ top: 12 })

          Text('提示：先凭记忆回想，再翻转核对；左滑下一张，右滑进收藏')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 14 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: 100 + this.safeBottom })
      // 底部预留 100vp 悬浮 Tab 栏空间（高度 56 + 顶部 8 + 底部 28 + 自身 safeBottom），
      // 避免按钮/TTS/提示被悬浮 Tab 栏遮挡
  }
}

// 预览专用：mock 一张速记卡，Previewer 无需 DataStore
@Preview
@Component
struct FlashcardPreview {
  build() {
    Column() {
      Row() {
        Text('速记卡')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: SPACE.lg, top: SPACE.md, bottom: SPACE.md })

      Column() {
        Text('综合分析类 · 三大要点')
          .fontSize(13)
          .fontColor($r('app.color.brand'))
          .margin({ bottom: SPACE.sm })
        Text('表态—分析—对策')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: SPACE.lg })
        Text('点亮/滑动翻转')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('90%')
      .height(280)
      .padding(SPACE.lg)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.lg)
      .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding(16)
  }
}

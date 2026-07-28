// 速记卡 Tab（百词斩式翻转卡）：左滑下一张、右滑收藏当前卡；点击翻转看详解
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { Section } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { ReaderIcon } from '../utils/SpeechReader';
import { PageHeader, EmptyState, IconTile, ProgressRing } from '../utils/Ui';
import { FavStore } from '../utils/FavStore';

interface Card {
  id: string;      // 所属文章 id（用于收藏）
  title: string;
  body: string;
}

@Component
export struct FlashcardView {
  @State cards: Card[] = [];
  @State idx: number = 0;
  @State flipped: boolean = false;   // 翻转状态：false=正面(要点) true=背面(详解)
  @State mastered: Set<string> = new Set<string>();  // 已掌握卡片标题集合（持久化）
  @State favSet: Set<string> = new Set<string>();    // 已收藏文章 id 集合（同步星标）
  @Consume pageStack: NavPathStack;
  // 订阅字号变化，触发本常驻 Tab 重渲染（FONT getter 实时读取 AppStorage('fontScale')）
  @StorageProp('fontScale') _fs: number = 1;

  private prefs: preferences.Preferences | null = null;
  private readonly PREF_NAME: string = 'flashcard_progress';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    // 同步收藏状态到星标
    FavStore.getIds().then((ids: string[]) => { this.favSet = new Set<string>(ids); });
    // 加载卡片
    DataStore.load(ctx).then(() => {
      const d = DataStore.data;
      const list: Card[] = [];
      d.articles
        .filter((a) => a.category === '考情' || a.category === '题型方法')
        .forEach((a) => {
          a.sections.forEach((s: Section) => {
            if (s.body.trim().length > 10) {
              list.push({ id: a.id, title: a.title + (s.heading ? ' · ' + s.heading : ''), body: s.body });
            }
          });
        });
      this.cards = list;
      this.restoreProgress();
    });
    // 进度持久化存储（与数据加载解耦，二者就绪后各自触发一次 restore，幂等）
    preferences.getPreferences(ctx, this.PREF_NAME).then((p: preferences.Preferences) => {
      this.prefs = p;
      this.restoreProgress();
    });
  }

  // 切换卡片时复位翻转，并保存进度
  private go(delta: number): void {
    const next: number = this.idx + delta;
    if (next < 0 || next >= this.cards.length) return;
    this.idx = next;
    this.flipped = false;
    this.saveProgress();
  }

  private toggleFlip(): void {
    this.flipped = !this.flipped;
  }

  // 标记为已掌握并自动下一张（主动回忆训练闭环）
  private markMaster(): void {
    const c: Card | undefined = this.cards[this.idx];
    if (c && !this.mastered.has(c.title)) {
      const s: Set<string> = new Set<string>(this.mastered);
      s.add(c.title);
      this.mastered = s;
    }
    this.saveProgress();
    this.go(1);
  }

  // 右滑：收藏 / 取消收藏当前卡（在卡片流内完成，并给出 Toast 反馈）
  private favoriteCurrent(): void {
    const c: Card | undefined = this.cards[this.idx];
    if (!c) return;
    FavStore.toggle(c.id).then((now: boolean) => {
      const s: Set<string> = new Set<string>(this.favSet);
      if (now) { s.add(c.id); } else { s.delete(c.id); }
      this.favSet = s;
      promptAction.showToast({ message: now ? '已收藏 ⭐' : '已取消收藏', duration: 1500 });
    });
  }

  // 左滑下一个；右滑收藏当前卡
  private onSwipe(angle: number): void {
    if (angle < 0) {
      this.go(1);
    } else {
      this.favoriteCurrent();
    }
  }

  // 读取持久化进度（当前位置 + 已掌握集合）
  private restoreProgress(): void {
    if (!this.prefs || this.cards.length === 0) return;
    const i: number = this.prefs.getSync('idx', 0) as number;
    this.idx = Math.min(Math.max(i, 0), this.cards.length - 1);
    const raw: string = this.prefs.getSync('mastered', '[]') as string;
    try {
      this.mastered = new Set<string>(JSON.parse(raw) as string[]);
    } catch (e) {
      this.mastered = new Set<string>();
    }
  }

  // 保存进度（当前位置 + 已掌握集合）
  private saveProgress(): void {
    if (!this.prefs) return;
    this.prefs.putSync('idx', this.idx);
    this.prefs.putSync('mastered', JSON.stringify(Array.from(this.mastered)));
    this.prefs.flush();
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 品牌头部
      PageHeader({ title: '速记卡' })

        if (this.cards.length === 0) {
          EmptyState({ emoji: '⏳', text: '加载中…' })
        } else {
          // 进度行：翻面标签 + 收藏入口 + 掌握度 + 位置环 + 计数
          Row() {
            Column() {
              Text(this.flipped ? '详解' : '要点')
                .fontSize(FONT.title)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.brand'))
              Text('⭐ 我的收藏')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.brand'))
                .margin({ top: SPACE.xs })
                .onClick(() => this.pageStack.pushPathByName('Favorites', {} as Record<string, Object>))
              Text(`✓ 已掌握 ${this.mastered.size}/${this.cards.length}`)
                .fontSize(FONT.mini)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: SPACE.xs })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            ProgressRing({ value: this.idx + 1, total: this.cards.length, dim: 38, color: $r('app.color.brand') })
            Text(`${this.idx + 1}/${this.cards.length}`)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: SPACE.sm })
          }
          .width('88%')
          .margin({ top: SPACE.md, bottom: SPACE.sm })

          // 百词斩式：大卡片居中，点击翻转；左右滑切换/收藏
          Stack() {
            // 收藏星标（仅展示，不影响翻转点击）
            Text(this.favSet.has(this.cards[this.idx].id) ? '★' : '☆')
              .fontSize(22)
              .fontColor(this.favSet.has(this.cards[this.idx].id) ? $r('app.color.brand') : $r('app.color.text_hint'))
              .position({ top: 12, right: 12 })
              .zIndex(1)

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
              // 已掌握标记
              if (this.mastered.has(this.cards[this.idx].title)) {
                Text('✓ 已掌握')
                  .fontSize(FONT.caption)
                  .fontColor($r('app.color.brand'))
                  .backgroundColor($r('app.color.brand_light'))
                  .borderRadius(RADIUS.sm)
                  .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                  .margin({ top: SPACE.sm })
              }
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

          // 底部操作：上一张 / 翻转 / 下一张
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

          // 主动回忆：认识 / 不认识（标记掌握度，持久化进度）
          Row({ space: 12 }) {
            Button('不认识')
              .fontSize(FONT.bodySm)
              .height(42)
              .layoutWeight(1)
              .backgroundColor($r('app.color.btn_neutral_bg'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(RADIUS.pill)
              .onClick(() => this.go(1))
            Button('认识 ✓')
              .fontSize(FONT.bodySm)
              .height(42)
              .layoutWeight(1)
              .backgroundColor($r('app.color.brand'))
              .fontColor($r('app.color.on_primary'))
              .borderRadius(RADIUS.pill)
              .onClick(() => this.markMaster())
          }
          .width('88%')
          .margin({ top: SPACE.sm })

          // 语音播报：朗读当前可见面（正面要点 / 背面详解）
          // id 含 idx 与翻面状态，切卡/翻面即视为新的朗读目标
          ReaderIcon({
            readId: 'card:' + this.idx + (this.flipped ? ':b' : ':f'),
            title: this.cards[this.idx].title,
            text: this.flipped ? this.cards[this.idx].body : this.cards[this.idx].title,
            label: '朗读当前面'
          })
          .margin({ top: 12 })

          Text('提示：先凭记忆回想，再翻转核对；左滑下一张，右滑收藏当前卡')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 14 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: this.safeBottom })
      // 官方系统 Tab 栏已位于内容区下方，底部仅留系统安全区，
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

// 速记卡搜集：瀑布流浏览全部速记卡片，支持搜索、按掌握度筛选，点击查看详情
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { Section } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { EmptyState } from '../utils/Ui';

interface CollectionCard {
  id: string;
  title: string; // 同时作为「已掌握」匹配键，与速记卡 Tab 保存的标题（a.title + 小节标题）完全一致
  body: string;
  category: string;
  mastered: boolean;
}

@Component
export struct FlashcardCollection {
  @State rawCards: CollectionCard[] = [];       // 全部卡片（含掌握度标记）
  @State filteredCards: CollectionCard[] = [];  // 经筛选后的卡片列表（@State，供 ForEach 观察）
  @State kw: string = '';                       // 搜索关键词
  @State filterMastery: string = 'all';         // 'all' | 'mastered' | 'unmastered'
  @State detailCard: CollectionCard | null = null;  // 当前查看详情的卡片
  @Consume pageStack: NavPathStack;

  private masteredTitles: Set<string> = new Set<string>();

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    // 先加载掌握度，再加载卡片数据；二者就绪后合并
    preferences.getPreferences(ctx, 'flashcard_progress').then((p: preferences.Preferences) => {
      const raw: string = p.getSync('mastered', '[]') as string;
      try {
        this.masteredTitles = new Set<string>(JSON.parse(raw) as string[]);
      } catch (e) {
        this.masteredTitles = new Set<string>();
      }
      if (this.rawCards.length > 0) {
        this.applyMasteryAndFilter();
      }
    });
    DataStore.load(ctx).then(() => {
      this.buildCards();
    });
  }

  // 构建卡片（与速记卡 Tab 一致：仅「考情」「题型方法」分类的文章段落）
  private buildCards(): void {
    const d = DataStore.data;
    const list: CollectionCard[] = [];
    d.articles
      .filter((a) => a.category === '考情' || a.category === '题型方法')
      .forEach((a) => {
        a.sections.forEach((s: Section) => {
          if (s.body.trim().length > 10) {
            const title: string = a.title + (s.heading ? ' · ' + s.heading : '');
            list.push({
              id: a.id,
              title: title,
              body: s.body,
              category: a.category,
              mastered: false
            });
          }
        });
      });
    this.rawCards = list;
    this.applyMasteryAndFilter();
  }

  // 将已掌握标记写入卡片，并刷新筛选结果
  private applyMasteryAndFilter(): void {
    this.rawCards = this.rawCards.map((c: CollectionCard): CollectionCard => {
      return {
        id: c.id,
        title: c.title,
        body: c.body,
        category: c.category,
        mastered: this.masteredTitles.has(c.title)
      };
    });
    this.refreshFilter();
  }

  // 根据 kw + filterMastery 更新 filteredCards（@State，供 ForEach 观察）
  private refreshFilter(): void {
    let result: CollectionCard[] = [...this.rawCards];
    if (this.filterMastery === 'mastered') {
      result = result.filter((c: CollectionCard): boolean => c.mastered);
    } else if (this.filterMastery === 'unmastered') {
      result = result.filter((c: CollectionCard): boolean => !c.mastered);
    }
    const k: string = this.kw.trim().toLowerCase();
    if (k) {
      result = result.filter((c: CollectionCard): boolean =>
        c.title.toLowerCase().includes(k) || c.body.toLowerCase().includes(k));
    }
    this.filteredCards = result;
  }

  // 当前全部卡片中已掌握数（公开 getter，供 build 读取；与 Practice.ets 模式一致）
  get masteredCount(): number {
    return this.rawCards.filter((c: CollectionCard): boolean => c.mastered).length;
  }

  // 点击卡片，弹出详情浮层
  private showDetail(card: CollectionCard): void {
    this.detailCard = card;
  }

  // 关闭详情
  private closeDetail(): void {
    this.detailCard = null;
  }

  // 单张瀑布流卡片
  @Builder
  cardItem(card: CollectionCard) {
    Column() {
      // 分类徽标
      Text(card.category)
        .fontSize(FONT.mini)
        .fontColor(card.category === '考情' ? $r('app.color.brand') : $r('app.color.accent'))
        .backgroundColor(card.category === '考情' ? $r('app.color.brand_light') : $r('app.color.accent_soft'))
        .borderRadius(RADIUS.sm)
        .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: SPACE.sm })

      // 标题
      Text(card.title)
        .fontSize(FONT.bodySm)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: SPACE.xs })

      // 正文预览
      Text(card.body)
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(18)
        .margin({ bottom: SPACE.sm })

      // 底部：掌握度状态
      Row() {
        Text(card.mastered ? '✓ 已掌握' : '○ 未掌握')
          .fontSize(FONT.mini)
          .fontColor(card.mastered ? $r('app.color.brand') : $r('app.color.text_tertiary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(SPACE.md)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .shadow({ radius: 8, color: $r('app.color.card_stroke'), offsetY: 2 })
    .onClick(() => { this.showDetail(card); })
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Stack() {
      // 主内容区
      Column() {
        BackHeader({ title: '速记卡搜集' })

        // 搜索栏（胶囊形）
        Row() {
          Text('🔍')
            .fontSize(16)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: SPACE.md, right: SPACE.sm })
          TextInput({ placeholder: '搜索卡片标题或内容', text: this.kw })
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.transparent'))
            .padding({ left: SPACE.sm })
            .onChange((v: string) => {
              this.kw = v;
              this.refreshFilter();
            })
          if (this.kw) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ right: SPACE.md })
              .onClick(() => {
                this.kw = '';
                this.refreshFilter();
              })
          }
        }
        .width('92%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.pill)
        .margin({ top: SPACE.md, bottom: SPACE.sm })
        .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })

        // 筛选行：三胶囊 + 已掌握统计
        Row() {
          Row({ space: SPACE.sm }) {
            MasteryChip({ label: '全部', selected: this.filterMastery === 'all',
              onTap: (): void => { this.filterMastery = 'all'; this.refreshFilter(); } })
            MasteryChip({ label: '已掌握', selected: this.filterMastery === 'mastered',
              onTap: (): void => { this.filterMastery = 'mastered'; this.refreshFilter(); } })
            MasteryChip({ label: '未掌握', selected: this.filterMastery === 'unmastered',
              onTap: (): void => { this.filterMastery = 'unmastered'; this.refreshFilter(); } })
          }
          .layoutWeight(1)

          Text(`已掌握 ${this.masteredCount ?? 0}/${this.rawCards.length ?? 0}`)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('92%')
        .margin({ bottom: SPACE.sm })

        // 状态：加载中
        if (this.rawCards.length === 0) {
          EmptyState({ emoji: '⏳', text: '加载中…' })
        }
        // 状态：筛选后无结果
        else if (this.filteredCards.length === 0) {
          EmptyState({
            emoji: '🔍',
            text: this.kw.trim() ? `没有匹配「${this.kw.trim()}」的卡片` : '该分类下暂无卡片'
          })
        }
        // 瀑布流
        else {
          WaterFlow() {
            ForEach(this.filteredCards, (card: CollectionCard, index: number) => {
              FlowItem() {
                this.cardItem(card)
              }
              .width('100%')
            }, (card: CollectionCard, index: number) => `${card.id}_${index}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(SPACE.sm)
          .rowsGap(SPACE.sm)
          .width('92%')
          .layoutWeight(1)
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: this.safeBottom + SPACE.lg })

      // 详情浮层（遮罩 + 半屏面板）
      if (this.detailCard) {
        // 半透明遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => { this.closeDetail(); })

        // 详情面板
        Column() {
          // 关闭按钮行
          Row() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('app.color.text_secondary')])
              .onClick(() => { this.closeDetail(); })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .margin({ bottom: SPACE.md })

          // 分类 + 掌握度标签
          Row() {
            Text(this.detailCard!.category)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_light'))
              .borderRadius(RADIUS.sm)
              .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
            Blank()
            Text(this.detailCard!.mastered ? '✓ 已掌握' : '○ 未掌握')
              .fontSize(FONT.caption)
              .fontColor(this.detailCard!.mastered ? $r('app.color.brand') : $r('app.color.text_secondary'))
              .backgroundColor(this.detailCard!.mastered ? $r('app.color.brand_light') : $r('app.color.tag_bg'))
              .borderRadius(RADIUS.sm)
              .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
          }
          .width('100%')
          .margin({ bottom: SPACE.md })

          // 完整标题
          Text(this.detailCard!.title)
            .fontSize(FONT.title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ bottom: SPACE.md })

          // 完整正文（可滚动）
          Scroll() {
            Text(this.detailCard!.body)
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .lineHeight(26)
              .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('92%')
        .height('72%')
        .padding(SPACE.lg)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.lg)
        .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 8 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

// 掌握度筛选胶囊：用独立组件 + @Prop selected，保证选中态可靠随 @State 重渲染
// （@Builder 传派生布尔参数不会稳定更新选中样式，故此处改用组件，与 Settings.ets 的 SegButton 一致）
@Component
struct MasteryChip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(FONT.caption)
      .fontColor(this.selected ? $r('app.color.on_primary') : $r('app.color.text_primary'))
      .backgroundColor(this.selected ? $r('app.color.brand') : $r('app.color.surface'))
      .borderRadius(RADIUS.sm)
      .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
      .onClick(() => {
        this.onTap();
      })
  }
}

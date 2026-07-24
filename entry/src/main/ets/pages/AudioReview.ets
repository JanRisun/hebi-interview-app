// 音频作答点评页：题目回顾 + AI 评分 / 点评 / AI 润色 / 解析与示范（逐字稿=题目 answerScript）
// 布局：BackHeader + 横向 sticky Tab 栏（随滚动常驻顶部）+ 纵向滚动卡片内容；点击 Tab 滚动到对应小节。
import { DataStore } from '../model/DataStore';
import { Question } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';

// 路由参数：题目 id（用于拉取题目内容作为「答题」小节）
interface AudioReviewParam {
  id: string;
}

@Component
export struct AudioReviewView {
  @Prop params: Object;
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  @Consume pageStack: NavPathStack;

  @State question: Question | null = null;
  @State activeTab: number = 0;                         // 当前高亮的 tab
  @State sectionOffsets: number[] = [0, 0, 0, 0, 0];     // 5 个小节相对 Scroll 内部的 yOffset

  @State foldExpanded: boolean = false;                 // 「解析与示范」长文本是否展开
  @State scriptNeedFold: boolean = false;               // 参考解析是否需要折叠（超出默认 8 行）
  @State scriptContentWidth: number = 0;                // 「解析与示范」卡片内文本可用宽度（vp），布局后获取

  private scroller: Scroller = new Scroller();
  private readonly tabs: string[] = ['答题', '得分', '点评', 'AI润色', '解析与示范'];

  aboutToAppear(): void {
    const p: AudioReviewParam | null = this.params as AudioReviewParam;
    if (p && p.id) {
      this.question = DataStore.questionById(p.id) ?? null;
    }
  }

  // 点击 Tab：滚动到对应小节。offset 由 onAreaChange 在布局后填充
  private scrollToTab(idx: number): void {
    this.activeTab = idx;
    const y: number = this.sectionOffsets[idx];
    if (y > 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: y - SPACE.sm });
    }
  }

  // 监听小节位置变化，把 yOffset 缓存下来供 scrollTo 使用
  private onSectionArea(idx: number, _oldArea: Area, newA: Area): void {
    const next: number[] = [...this.sectionOffsets];
    next[idx] = newA.position.y as number;
    this.sectionOffsets = next;
  }

  // 依据卡片实际宽度估算参考解析行数：中文为主，每行约容纳 (宽度/字号) 个字符；超过 8 行则显示折叠按钮
  private updateFold(): void {
    if (!this.question || this.scriptContentWidth <= 0) {
      this.scriptNeedFold = false;
      return;
    }
    const textWidth: number = this.scriptContentWidth - 2 * SPACE.lg; // 减去卡片左右内边距
    if (textWidth <= 0) {
      this.scriptNeedFold = false;
      return;
    }
    const charsPerLine: number = Math.max(1, Math.floor(textWidth / FONT.body));
    const lines: number = Math.ceil((this.question.answerScript?.length ?? 0) / charsPerLine);
    this.scriptNeedFold = lines > 8;
  }

  build() {
    Column() {
      // sticky：标题栏
      BackHeader({ title: '答题点评' })

      // sticky：横向 Tab 栏
      this.tabBar()

      // 滚动内容
      Scroll(this.scroller) {
        Column() {
          this.answerSection()
          this.scoreSection()
          this.reviewSection()
          this.aiPolishSection()
          this.analysisTranscriptSection()
        }
        .width('100%')
        .padding({ bottom: SPACE.xl + this.safeBottom })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor($r('app.color.background'))
      .onScroll(() => {
        // 滚动时根据当前位置自动高亮最接近的 tab
        const y: number = this.scroller.currentOffset().yOffset;
        let nearest: number = 0;
        let minDist: number = Number.MAX_VALUE;
        for (let i: number = 0; i < this.sectionOffsets.length; i++) {
          const d: number = Math.abs(this.sectionOffsets[i] - y);
          if (d < minDist) {
            minDist = d;
            nearest = i;
          }
        }
        if (nearest !== this.activeTab) {
          this.activeTab = nearest;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding({ top: this.safeTop })
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
  }

  // ---- 顶部 Tab 栏（横向滚动 + 选中高亮 + 品牌色下划线） ----
  @Builder tabBar() {
    Row() {
      Scroll() {
        Row({ space: SPACE.lg }) {
          ForEach(this.tabs, (label: string, idx: number): void => {
            this.tabItem(label, idx);
          })
        }
        .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.md, bottom: SPACE.md })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .border({
      width: { bottom: 1 },
      color: $r('app.color.divider')
    })
  }

  @Builder tabItem(label: string, idx: number) {
    Column() {
      Text(label)
        .fontSize(FONT.body)
        .fontWeight(this.activeTab === idx ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === idx ? $r('app.color.brand') : $r('app.color.text_secondary'))
      Row()
        .width(this.activeTab === idx ? 24 : 0)
        .height(3)
        .borderRadius(2)
        .margin({ top: 6 })
        .backgroundColor(this.activeTab === idx ? $r('app.color.brand') : Color.Transparent)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.scrollToTab(idx);
    })
  }

  // ---- 通用小节标题（小节卡片顶部，标题前加品牌色短横线） ----
  @Builder sectionTitle(label: string) {
    Row() {
      Row()
        .width(3)
        .height(14)
        .borderRadius(2)
        .backgroundColor($r('app.color.brand'))
        .margin({ right: SPACE.sm })
      Text(label)
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: SPACE.md })
  }

  // ---- 答题小节：题干 + 提示 + 时长信息 ----
  @Builder answerSection() {
    Column() {
      this.sectionTitle('答题')
      Text(this.question ? this.question.title : '暂无题目内容')
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .margin({ bottom: SPACE.sm })
      Text(this.question ? this.question.prompt : '请确认题目数据是否正确加载。')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
      // 答题基础信息
      Row({ space: SPACE.xl }) {
        this.metaChip('思考时长', '12 秒')
        this.metaChip('作答时长', '45 秒')
      }
      .margin({ top: SPACE.md })
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec0')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(0, oldA, newA);
    })
  }

  @Builder metaChip(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 得分小节：分数大字 + 等级 + 维度评分 ----
  @Builder scoreSection() {
    Column() {
      this.sectionTitle('得分')
      Row() {
        Column() {
          Text('85')
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text('综合分')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)

        Row()
          .width(1)
          .height(40)
          .backgroundColor($r('app.color.divider'))
          .margin({ left: SPACE.xl, right: SPACE.xl })

        Column() {
          Text('良好')
            .fontSize(FONT.title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Text('回答条理清晰，建议进一步丰富细节')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 维度评分
      Column() {
        this.scoreRow('内容完整度', 0.88)
        this.scoreRow('逻辑条理', 0.82)
        this.scoreRow('语言表达', 0.86)
        this.scoreRow('亮点 / 创新', 0.78)
      }
      .width('100%')
      .margin({ top: SPACE.md })
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec1')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(1, oldA, newA);
    })
  }

  @Builder scoreRow(label: string, ratio: number) {
    Row() {
      Text(label)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
      // 进度条
      Row() {
        Row()
          .height('100%')
          .width(`${ratio * 100}%`)
          .backgroundColor($r('app.color.brand'))
          .borderRadius(3)
      }
      .width('50%')
      .height(6)
      .backgroundColor($r('app.color.surface_variant'))
      .borderRadius(3)
      .margin({ left: SPACE.md, right: SPACE.md })

      Text(`${Math.round(ratio * 100)}`)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.brand'))
        .fontWeight(FontWeight.Bold)
        .width(32)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .margin({ top: SPACE.sm })
  }

  // ---- 点评小节：AI 评语（多段）+ 标签 ----
  @Builder reviewSection() {
    Column() {
      this.sectionTitle('点评')
      Text('回答结构完整，能紧扣题意展开论述，观点明确，论据较充分。')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
        .margin({ bottom: SPACE.sm })
      Text('建议在第二点论述中补充具体案例，可进一步增强说服力；同时注意口语化表达，可适当精简。')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
      Row({ space: SPACE.sm }) {
        this.tagChip('思路清晰')
        this.tagChip('论据充分')
        this.tagChip('可再精简')
      }
      .margin({ top: SPACE.md })
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec2')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(2, oldA, newA);
    })
  }

  @Builder tagChip(text: string) {
    Text(text)
      .fontSize(FONT.caption)
      .fontColor($r('app.color.brand'))
      .padding({ left: SPACE.sm, right: SPACE.sm, top: 4, bottom: 4 })
      .borderRadius(RADIUS.pill)
      .backgroundColor($r('app.color.brand_light'))
  }

  // ---- AI 润色小节：润色前后对比 ----
  @Builder aiPolishSection() {
    Column() {
      this.sectionTitle('AI 润色')
      Text('润色前')
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
      Text('我觉得这个事情挺重要的，因为我们现在面对的这个问题，其实从大方向来看，是一个比较长期的过程。')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
        .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
        .margin({ top: SPACE.xs, bottom: SPACE.md })
        .borderRadius(RADIUS.md)
        .backgroundColor($r('app.color.surface_variant'))

      Text('润色后')
        .fontSize(FONT.caption)
        .fontColor($r('app.color.brand'))
      Text('这一议题至关重要。当前我们所面对的挑战，本质上是一项需要长期推进的系统性工作。')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(22)
        .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
        .margin({ top: SPACE.xs })
        .borderRadius(RADIUS.md)
        .backgroundColor($r('app.color.brand_light'))
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec3')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(3, oldA, newA);
    })
  }

  // ---- 解析与示范小节：对应题目页底部「解析与示范」，内容取自题目 answerScript ----
  @Builder analysisTranscriptSection() {
    Column() {
      this.sectionTitle('解析与示范')
      // 参考解析（与题目页一致的展示：answerScript）
      Text('参考解析')
        .fontSize(FONT.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_title'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: SPACE.sm })
      // 主显示文本：默认 8 行，超出省略；展开后显示全文
      Text(this.question ? this.question.answerScript : '暂无解析内容')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
        .width('100%')
        .alignSelf(ItemAlign.Start)
        .maxLines(this.foldExpanded ? 1000 : 8)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.scriptNeedFold) {
        Text(this.foldExpanded ? '收起' : '展开全文')
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.brand'))
          .margin({ top: SPACE.sm })
          .alignSelf(ItemAlign.End)
          .onClick(() => {
            this.foldExpanded = !this.foldExpanded;
          })
      }
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec4')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(4, oldA, newA);
      this.scriptContentWidth = newA.width as number;
      this.updateFold();
    })
  }

}
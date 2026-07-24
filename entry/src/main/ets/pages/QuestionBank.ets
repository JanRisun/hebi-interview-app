// 真题库二级页：顶部搜索框 + 下方真题列表（平铺，可搜索）
// 从个人中心「真题库」卡 push 进入，返回走 BackHeader；点击真题进入 Detail。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Question } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { PageHeader, IconTile, EmptyState, HighlightText } from '../utils/Ui';

// 详情路由参数（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface DetailParam { id: string; kind: string; kw?: string }

@Component
export struct QuestionBankView {
  @State data: AppData | null = null;
  @State kw: string = '';          // 搜索框内容（空=显示全部真题，非空=本页真题内全文检索）
  @Prop root: boolean = false;     // true=底部主 Tab（无返回键，标题「题库」）；false=个人中心二级页
  @State bankFilter: string = '全部'; // 真题 / 母题 筛选
  private bankFilters: string[] = ['全部', '真题', '母题'];
  private listScroller: Scroller = new Scroller(); // 列表滚动控制器，用于切换筛选/搜索时回到顶部
  @Consume pageStack: NavPathStack;

  aboutToAppear(): void {
    DataStore.load(getContext(this) as common.UIAbilityContext).then((d: AppData) => {
      this.data = d;
    });
  }

  // 真题内全文检索：标题 / 来源 / 题型 / 标签 / 题干 / 答案
  private matchQuestion(q: Question, k: string): boolean {
    const s: string = k.toLowerCase();
    if (q.title.toLowerCase().includes(s)) return true;
    if (q.source.toLowerCase().includes(s)) return true;
    if (q.type.toLowerCase().includes(s)) return true;
    if (q.tags.some((t: string): boolean => t.toLowerCase().includes(s))) return true;
    if (q.prompt.toLowerCase().includes(s)) return true;
    if (q.answerScript.toLowerCase().includes(s)) return true;
    return false;
  }

  // 真题 / 母题 判别（依据来源字段）
  private isReal(q: Question): boolean {
    const s: string = (q.source ?? '').toLowerCase();
    return s.includes('真题') || s.includes('浚县') || s.includes('事业编') || s.includes('公务员') ||
      s.includes('省考') || s.includes('国考');
  }
  private isMother(q: Question): boolean {
    const s: string = (q.source ?? '').toLowerCase();
    return s.includes('母题') || s.includes('套题') || s.includes('模拟');
  }

  // 当前检索命中结果：先按真题/母题筛选，再按关键词全文检索（kw 为空且不过滤时返回全部）
  private searchHits(): Question[] {
    if (!this.data) return [];
    const q: string = this.kw.trim().toLowerCase();
    return this.data.questions.filter((x: Question): boolean => {
      if (this.bankFilter === '真题' && !this.isReal(x)) return false;
      if (this.bankFilter === '母题' && !this.isMother(x)) return false;
      if (!q) return true;
      return this.matchQuestion(x, q);
    });
  }

  // 进入真题详情
  private openQuestion(q: Question): void {
    const params: DetailParam = { id: q.id, kind: 'question', kw: this.kw };
    this.pageStack.pushPathByName('Detail', params);
  }

  // 真题行：图标 + 标题 + 来源 + 标签 chips（最多 3 个）+ 箭头
  @Builder questionRow(q: Question) {
    Row() {
      IconTile({ emoji: '❓', bg: $r('app.color.accent_soft'), fg: $r('app.color.accent'), dim: 44 })
        .margin({ right: SPACE.md })
      Column() {
        HighlightText({ text: q.title, kw: this.kw, fontSize: FONT.body, baseColor: $r('app.color.text_primary'), hitColor: $r('app.color.brand'), singleLine: true })
          .width('100%')
        HighlightText({ text: q.source, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), hitColor: $r('app.color.brand'), singleLine: true })
          .margin({ top: SPACE.xs })
          .width('100%')
        if (q.tags && q.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(q.tags.slice(0, 3), (t: string) => {
              Text(t)
                .fontSize(FONT.mini)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.xs, right: SPACE.xs })
            }, (t: string) => t)
            if (q.tags.length > 3) {
              Text('+' + (q.tags.length - 3))
                .fontSize(FONT.mini)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: SPACE.xs })
            }
          }
          .width('100%')
        }
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
    .onClick(() => this.openQuestion(q))
  }

  // 真题列表（含检索态空态；撑满剩余高度，空态居中、有数据贴顶）
  @Builder list() {
    Column() {
      if (this.searchHits().length === 0) {
        EmptyState({ emoji: '🔍', text: this.kw.trim() ? `没有匹配「${this.kw.trim()}」的真题` : '该分类下暂无真题' })
      } else {
        Scroll(this.listScroller) {
          Column() {
            ForEach(this.searchHits(), (q: Question) => {
              this.questionRow(q)
            }, (q: Question) => q.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('92%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(this.searchHits().length === 0 ? FlexAlign.Center : FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  // 真题 / 母题 筛选条 + 结果数
  @Builder filterBar() {
    Column() {
      Row({ space: SPACE.xs }) {
        ForEach(this.bankFilters, (f: string) => {
          Text(f)
            .fontSize(FONT.caption)
            .fontColor(this.bankFilter === f ? $r('app.color.brand') : $r('app.color.text_secondary'))
            .backgroundColor(this.bankFilter === f ? $r('app.color.brand_light') : $r('app.color.surface'))
            .borderRadius(RADIUS.pill)
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.xs, bottom: SPACE.xs })
            .onClick(() => {
              if (this.bankFilter === f) return;
              this.bankFilter = f;
              this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 }); // 切换筛选后回到列表顶部
            })
        }, (f: string) => f)
      }
      .width('100%')
      Text(`${this.searchHits().length} 题`)
        .fontSize(FONT.mini)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: SPACE.xs })
        .width('100%')
    }
    .width('92%')
    .alignSelf(ItemAlign.Center)
    .margin({ top: SPACE.sm, bottom: SPACE.xs })
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 头部：主 Tab 用 PageHeader（无返回键），二级页用 BackHeader（带返回键）
      if (this.root) {
        PageHeader({ title: '题库' })
      } else {
        BackHeader({ title: '真题库' })
      }

      // 顶部搜索框（胶囊形 + 搜索图标 + 清空），输入即在本页真题内实时检索
      Row() {
        Text('🔍')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: SPACE.md, right: SPACE.sm })
        TextInput({ placeholder: '搜索真题 / 母题', text: this.kw })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.transparent'))
          .padding({ left: SPACE.sm })
          .onChange((v: string) => {
            this.kw = v;
            this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 }); // 搜索词变化时回到列表顶部
          })
        if (this.kw) {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(18)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ right: SPACE.md })
            .onClick(() => {
              this.kw = '';
            })
        }
      }
      .width('92%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.pill)
      .margin({ bottom: SPACE.sm })
      .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })

      // 真题 / 母题 筛选 + 结果数
      this.filterBar()

      if (this.data) {
        this.list()
      } else {
        EmptyState({ emoji: '⏳', text: '加载中…' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 主 Tab（root=true）底部叠加 100vp 悬浮 Tab 栏空间（56 栏高 + 8 顶gap + 28 底gap + 自身 safeBottom），
    // 避免列表最后一项被悬浮 Tab 栏遮挡；二级页（root=false，无悬浮栏）只留系统 safeBottom。
    .padding({ top: this.safeTop, bottom: (this.root ? 100 : 0) + this.safeBottom })
  }
}

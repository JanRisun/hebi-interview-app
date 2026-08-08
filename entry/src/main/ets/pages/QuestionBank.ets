// 真题库二级页：顶部搜索框 + 下方真题列表（平铺，可搜索）
// 从个人中心「真题库」卡 push 进入，返回走 BackHeader；点击真题进入 Detail。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Question } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { PageHeader, IconTile, EmptyState, HighlightText, SearchBar } from '../utils/Ui';

// 详情路由参数（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface DetailParam { id: string; kind: string; kw?: string }

@Component
export struct QuestionBankView {
  @State data: AppData | null = null;
  @State kw: string = '';          // 搜索框内容（空=显示全部真题，非空=本页真题内全文检索）
  @Prop root: boolean = false;     // true=底部主 Tab（无返回键，标题「题库」）；false=个人中心二级页
  @State bankTab: number = 0;        // 当前分类 Tab 索引（对应 bankFilters）
  // 分类切换：综合分析、组织管理、应急应变、人际关系、情景模拟按 typeCat 匹配；
  // 真题 / 母题 按 source 匹配（见 matchBankFilter）。
  // 与知识库一致：使用 Tabs 横滑分段控件，下划线指示器，左右滑动切换。
  private bankFilters: string[] = ['全部', '综合分析', '组织管理', '应急应变', '人际关系', '情景模拟', '真题', '母题'];
  private listScroller: Scroller = new Scroller(); // 列表滚动控制器，用于切换筛选/搜索时回到顶部
  @Consume pageStack: NavPathStack;
  // 订阅字号变化，触发本常驻 Tab 重渲染（FONT getter 实时读取 AppStorage('fontScale')）
  @StorageProp('fontScale') _fs: number = 1;

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

  // 当前所选题型/真题/母题 标签是否命中（综合/组织/应急/人际/情景按 typeCat 精确匹配；真题/母题按来源判断）
  private matchBankFilter(q: Question, f: string): boolean {
    // 前 5 类为题型，直接比对 typeCat
    const typeCats: string[] = ['综合分析', '组织管理', '应急应变', '人际关系', '情景模拟'];
    if (typeCats.includes(f)) {
      return (q.typeCat ?? '') === f;
    }
    if (f === '真题') return this.isReal(q);
    if (f === '母题') return this.isMother(q);
    return true; // 全部
  }

  // 当前所选分类（bankTab → bankFilters[bankTab]）
  private get currentBankFilter(): string {
    return this.bankFilters[this.bankTab] ?? '全部';
  }

  // 按指定分类名筛题（不叠加 kw；kw 搜索是单独的 searchHitsByKw 流程）
  private questionsOf(filterName: string): Question[] {
    if (!this.data) return [];
    return this.data.questions.filter((x: Question): boolean => this.matchBankFilter(x, filterName));
  }

  // 跨分类的全文检索结果（搜索激活时使用，隐藏 Tab）
  private searchHits(): Question[] {
    if (!this.data) return [];
    const q: string = this.kw.trim().toLowerCase();
    if (!q) return [];
    return this.data.questions.filter((x: Question): boolean => this.matchQuestion(x, q));
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

  // 单分类列表（每个 TabContent 渲染自己分类下的题；结构与知识库 tabList 一致，保证 TabBar 高度统一）
  @Builder tabList(filterName: string) {
    if (this.questionsOf(filterName).length === 0) {
      EmptyState({ emoji: '🔍', text: '该分类下暂无真题' })
        .width('100%')
        .layoutWeight(1)
    } else {
      List({ scroller: this.listScroller }) {
        ForEach(this.questionsOf(filterName), (q: Question) => {
          ListItem() {
            this.questionRow(q)
          }
        }, (q: Question) => q.id)
      }
      .width('92%')
      .height('100%')
      .alignSelf(ItemAlign.Center)
      .margin({ top: SPACE.sm })
    }
  }

  // 跨分类全文检索结果（搜索激活时使用，隐藏 Tab）
  @Builder searchList() {
    Column() {
      if (this.searchHits().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw.trim()}」的真题` })
      } else {
        List() {
          ForEach(this.searchHits(), (q: Question) => {
            ListItem() {
              this.questionRow(q)
            }
          }, (q: Question) => q.id)
        }
        .width('92%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(this.searchHits().length === 0 ? FlexAlign.Center : FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  // 顶部题数条文案（在普通方法里计算，规避 @Builder 内不允许 declarative const）
  private countText(): string {
    const f: string = this.bankFilters[this.bankTab] ?? '全部';
    if (this.kw.trim()) {
      return `搜索到 ${this.searchHits().length} 题`;
    }
    return `${f} · ${this.questionsOf(f).length} 题`;
  }

  // 顶部题数条（搜索激活时显示「搜索命中 N 题」）
  @Builder countBar() {
    Text(this.countText())
      .fontSize(FONT.mini)
      .fontColor($r('app.color.text_tertiary'))
      .width('92%')
      .alignSelf(ItemAlign.Center)
      .margin({ top: SPACE.xs, bottom: SPACE.xs })
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

      // 顶部搜索框（公共 SearchBar，与知识库保持一致）
      SearchBar({
        kw: $kw,
        placeholder: '搜索真题 / 母题',
        onInput: (v: string) => {
          this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 }); // 搜索词变化时回到列表顶部
        }
      })

      // 题数条（暂隐藏）
      // this.countBar()

      if (this.data) {
        if (this.kw.trim()) {
          // 搜索激活：跨所有分类展示命中结果（隐藏 Tab）
          this.searchList()
        } else {
          // 浏览态：8 个分类 Tab 切换（与知识库一致：可左右侧滑）
          Tabs({ index: this.bankTab, barPosition: BarPosition.Start }) {
            ForEach(this.bankFilters, (t: string) => {
              TabContent() {
                this.tabList(t)
              }.tabBar(t)
            }, (t: string) => t)
          }
          .width('100%')
          .layoutWeight(1)
          .barMode(BarMode.Scrollable)
          .barHeight(56)
          .onChange((i: number) => {
            this.bankTab = i;
            this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 }); // 切换分类后回到列表顶部
          })
        }
      } else {
        EmptyState({ emoji: '⏳', text: '加载中…' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 主 Tab（root=true）底部叠加 100vp 悬浮 Tab 栏空间（56 栏高 + 8 顶gap + 28 底gap + 自身 safeBottom），
    // 首页 Tab（root=true）内容区位于官方系统 Tab 栏上方；二级页（root=false）为整屏子页；两者底部均只留系统 safeBottom。
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

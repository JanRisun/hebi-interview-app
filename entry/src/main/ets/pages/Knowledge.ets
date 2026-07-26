// 知识点二级页：顶部搜索框 + 6 个子分类 Tab（考情 / 题型方法 / 专项练习 / 主题专项 / 宣传类专项 / 索引）
// 从个人中心「知识点」卡 push 进入，返回走 BackHeader；点击文章进入 Detail。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { IconTile, EmptyState, HighlightText } from '../utils/Ui';

// 知识点内部 6 个子分类（与 data.json 中 article.category 取值严格对应，顺序即 Tab 顺序）
const K_TABS: string[] = ['考情', '题型方法', '专项练习', '主题专项', '宣传类专项', '政策素材', '素材积累', '索引', '经典理论'];

// 详情路由参数（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface DetailParam { id: string; kind: string; kw?: string; cat?: string }

@Component
export struct KnowledgeView {
  @State data: AppData | null = null;
  @State kw: string = '';          // 搜索框内容（空=按分类 Tab 浏览，非空=知识点内全文检索）
  @State activeTab: number = 0;    // 当前子分类 Tab 索引
  @Consume pageStack: NavPathStack;

  aboutToAppear(): void {
    DataStore.load(getContext(this) as common.UIAbilityContext).then((d: AppData) => {
      this.data = d;
    });
  }

  // 取某子分类下的知识点
  private articlesOf(cat: string): Article[] {
    if (!this.data) return [];
    return this.data.articles.filter((a: Article): boolean => a.category === cat);
  }

  // 知识点内全文检索：标题 / 摘要 / 标签 / 正文
  private matchArticle(a: Article, q: string): boolean {
    const k: string = q.toLowerCase();
    if (a.title.toLowerCase().includes(k)) return true;
    if (a.summary.toLowerCase().includes(k)) return true;
    if (a.tags.some((t: string): boolean => t.toLowerCase().includes(k))) return true;
    if (a.sections.some((s) => (s.heading + ' ' + s.body).toLowerCase().includes(k))) return true;
    return false;
  }

  // 当前检索命中结果（kw 为空时返回全部）
  private searchHits(): Article[] {
    if (!this.data) return [];
    const q: string = this.kw.trim();
    if (!q) return this.data.articles;
    return this.data.articles.filter((a: Article): boolean => this.matchArticle(a, q));
  }

  // 进入知识点详情
  private openArticle(a: Article): void {
    const params: DetailParam = { id: a.id, kind: 'article', kw: this.kw, cat: a.category };
    this.pageStack.pushPathByName('Detail', params);
  }

  // 知识点行：图标 + 标题 + 副标题 + 标签 chips（最多 3 个）+ 箭头
  @Builder essayRow(a: Article) {
    Row() {
      IconTile({ emoji: '📖', bg: $r('app.color.brand_light'), fg: $r('app.color.brand'), dim: 44 })
        .margin({ right: SPACE.md })
      Column() {
        HighlightText({ text: a.title, kw: this.kw, fontSize: FONT.body, baseColor: $r('app.color.text_primary'), hitColor: $r('app.color.brand'), singleLine: true })
          .width('100%')
        HighlightText({ text: a.summary ? a.summary : a.category, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), hitColor: $r('app.color.brand'), singleLine: true })
          .margin({ top: SPACE.xs })
          .width('100%')
        if (a.tags && a.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(a.tags.slice(0, 3), (t: string) => {
              Text(t)
                .fontSize(FONT.mini)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.xs, right: SPACE.xs })
            }, (t: string) => t)
            if (a.tags.length > 3) {
              Text('+' + (a.tags.length - 3))
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
    .onClick(() => this.openArticle(a))
  }

  // 单个子分类的列表
  @Builder tabList(cat: string) {
    List() {
      ForEach(this.articlesOf(cat), (a: Article) => {
        ListItem() {
          this.essayRow(a)
        }
      }, (a: Article) => a.id)
    }
    .width('92%')
    .height('100%')
    .alignSelf(ItemAlign.Center)
    .margin({ top: SPACE.sm })
  }

  // 搜索结果列表（知识点内全文检索，跨 6 个子分类）
  @Builder searchList() {
    // TabContent 默认会把子组件垂直居中且不拉伸，需显式撑满并贴顶
    Column() {
      if (this.searchHits().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw.trim()}」的知识点` })
      } else {
        List() {
          ForEach(this.searchHits(), (a: Article) => {
            ListItem() {
              this.essayRow(a)
            }
          }, (a: Article) => a.id)
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

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 子页头部（带返回）
      BackHeader({ title: '知识点' })

      // 顶部搜索框（胶囊形 + 搜索图标），输入即在本页知识点内实时检索
      Row() {
        Text('🔍')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: SPACE.md, right: SPACE.sm })
        TextInput({ placeholder: '搜索知识点', text: this.kw })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.transparent'))
          .padding({ left: SPACE.sm })
          .onChange((v: string) => {
            this.kw = v;
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

      if (this.data) {
        if (this.kw.trim()) {
          // 检索态：跨 6 个子分类展示命中结果（隐藏 Tab）
          this.searchList()
        } else {
          // 浏览态：6 个子分类 Tab 切换
          Tabs({ index: this.activeTab, barPosition: BarPosition.Start }) {
            ForEach(K_TABS, (t: string) => {
              TabContent() {
                this.tabList(t)
              }.tabBar(t)
            }, (t: string) => t)
          }
          .width('100%')
          .layoutWeight(1)
          .barMode(BarMode.Scrollable)
        }
      } else {
        EmptyState({ emoji: '⏳', text: '加载中…' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 知识库子页是整屏 NavDestination，进入后首页悬浮 Tab 栏已隐藏，底部只留系统安全区
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

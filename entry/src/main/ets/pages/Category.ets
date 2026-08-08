// 知识库 Tab（原「素材」）：复用个人中心「知识点」二级页面展示形式
//   - 顶部搜索框：输入即跨分类检索（胶囊 + 🔍 + 清空）
//   - 无搜索词时：按 6 个分类用 Tabs 展示知识点
//   - 有搜索词时：隐藏 Tabs，跨分类检索结果；空态居中、有数据贴顶
// 真题相关内容由「真题模考」Tab 与「真题库」承载，本页聚焦知识点知识库。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { PageHeader, EmptyState, IconTile, HighlightText, SearchBar } from '../utils/Ui';

// 二级页同款 6 个分类（与 Knowledge.ets 保持一致）
const K_TABS: string[] = ['题型方法', '专项练习', '主题专项', '宣传类专项', '政策素材', '素材积累', '索引', '经典理论', '考情'];

// 详情路由参数（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface DetailParam { id: string; kind: string; kw?: string; cat?: string }

@Component
export struct CategoryView {
  @State data: AppData | null = null;
  @State kw: string = '';
  @State activeTab: number = 0;
  @Consume pageStack: NavPathStack;
  // 订阅字号变化，触发本常驻 Tab 重渲染（FONT getter 实时读取 AppStorage('fontScale')）
  @StorageProp('fontScale') _fs: number = 1;

  aboutToAppear(): void {
    DataStore.load(getContext(this) as common.UIAbilityContext).then((d: AppData) => {
      this.data = d;
    });
  }

  // 某分类下的知识点
  private articlesOf(cat: string): Article[] {
    if (!this.data) return [];
    return this.data.articles.filter((a: Article) => a.category === cat);
  }

  // 单条命中：标题 / 摘要 / 正文任意包含关键词
  private matchArticle(a: Article, q: string): boolean {
    const kw: string = q.trim().toLowerCase();
    if (!kw) return true;
    if (a.title.toLowerCase().includes(kw)) return true;
    if ((a.summary ?? '').toLowerCase().includes(kw)) return true;
    if (a.tags.some((t: string): boolean => t.toLowerCase().includes(kw))) return true;
    if (a.sections.some((s) => (s.heading + ' ' + s.body).toLowerCase().includes(kw))) return true;
    return false;
  }

  // 跨分类检索结果
  private searchHits(): Article[] {
    if (!this.data) return [];
    const kw: string = this.kw.trim().toLowerCase();
    if (!kw) return [];
    return this.data.articles.filter((a: Article) => this.matchArticle(a, kw));
  }

  private openArticle(a: Article): void {
    const params: DetailParam = { id: a.id, kind: 'article', kw: this.kw.trim(), cat: a.category };
    this.pageStack.pushPathByName('Detail', params);
  }

  // 知识点行（与 Knowledge.ets 保持一致）
  @Builder
  private essayRow(a: Article) {
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

  // 浏览态：单个分类内容（与 Knowledge.ets / QuestionBank.ets 同款：List 撑满 + 居中 + 顶部间距）
  @Builder
  private tabList(cat: string) {
    if (this.articlesOf(cat).length === 0) {
      EmptyState({ emoji: '📭', text: `「${cat}」下还没有内容` })
        .width('100%')
        .layoutWeight(1)
    } else {
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
  }

  // 检索态：跨分类结果（空态居中、有数据贴顶）
  @Builder
  private searchList() {
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
      // 品牌头部（主 Tab 统一样式）
      PageHeader({ title: '知识库' })

      // 搜索框（公共 SearchBar，与 Knowledge.ets 保持一致）
      SearchBar({
        kw: $kw,
        placeholder: this.data ? `搜索 ${this.data.articles.length} 条知识点` : '搜索知识点'
      })

      if (!this.data) {
        EmptyState({ emoji: '⏳', text: '加载中…' })
      } else if (this.kw.trim()) {
        // 检索态：跨分类结果
        this.searchList()
      } else {
        // 浏览态：6 个分类 Tabs
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
        .barPosition(BarPosition.Start)
        .barHeight(56)
        .backgroundColor($r('app.color.background'))
        .onChange((idx: number) => {
          this.activeTab = idx;
        })
        .animationDuration(200)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

// 预览专用：mock 知识库，Previewer 无需 DataStore
@Preview
@Component
struct CategoryPreview {
  build() {
    Column() {
      Text('知识库')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: SPACE.lg, top: SPACE.md, bottom: SPACE.md })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding(16)
  }
}

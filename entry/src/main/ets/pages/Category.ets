// 素材 Tab：对应原「分类浏览」内容（知识点 / 真题库），顶部搜索框 → 全文检索
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { UserTagStore } from '../utils/UserTagStore';
import { LazyDataSource } from '../utils/LazySource';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile, TagChip, SectionTitle, PageHero, PageHeader, EmptyState } from '../utils/Ui';

// 导航参数透传对象（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface SearchParam { q: string }
interface DetailParam { id: string; kind: string }

// 预缓存分组项接口（ArkTS strict 禁止对象字面量作类型声明，必须用 interface）
interface ArticleGroup {
  cat: string;
  items: Article[];
}

@Component
export struct CategoryView {
  @State data: AppData | null = null;
  @State tab: string = 'articles';
  @State kw: string = '';   // 顶部搜索框内容
  @State filterTag: string = '';                       // 当前选中的用户标签筛选（''=不过滤）
  @State userTagPool: string[] = [];                   // 全部用户标签（用于筛选条）
  @State userTagMap: Record<string, string[]> = {};    // 内容id→用户标签（用于命中判断）
  // 预缓存：数据加载/标签切换时算一次，build 内不再实时 filter（避免每次重渲全量重算）
  @State grouped: ArticleGroup[] = [];                        // 按分类分组（未筛选态用）
  @State filteredArticles: Article[] = [];                       // 当前标签命中的文章（筛选态用）
  @State filteredQuestions: Question[] = [];                     // 当前标签命中的题目
  @Consume pageStack: NavPathStack;
  // 来自个人中心的跳转意图（AppStorage 透传）：materialSub=子标签(articles/questions)，
  // materialTag=标记筛选('__mytags__' 表示仅看我的标记)，materialNonce 自增以每次都触发 @Watch。
  @StorageLink('materialSub') navSub: string = 'articles';
  @StorageLink('materialTag') navTag: string = '';
  @StorageLink('materialNonce') @Watch('applyNav') navNonce: number = 0;
  // 数据源刷新靠 IDataSource 的 onDataReloaded 通知，无需 @State（@State 代理会破坏私有字段）
  groupDs: LazyDataSource<ArticleGroup> = new LazyDataSource<ArticleGroup>([]);
  articleDs: LazyDataSource<Article> = new LazyDataSource<Article>([]);
  questionDs: LazyDataSource<Question> = new LazyDataSource<Question>([]);

  // 订阅全局收藏/标签版本号：详情页加标签后自动刷新标记筛选，无需重启 app
  @StorageLink('favTagVersion') @Watch('onTagChange') tagVersion: number = 0;

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d) => {
      this.data = d;
      this.recompute();   // 数据就绪后预计算分组与筛选结果
    });
    this.refreshUserTags();
  }

  // 收藏/标签变更时触发（@Watch）：刷新用户标记并重算筛选
  private onTagChange(): void {
    this.refreshUserTags();
  }

  // 拉取最新用户标签（全部标签池 + 内容→标签映射），并按需重算筛选结果
  private refreshUserTags(): void {
    UserTagStore.allTags().then((t: string[]) => { this.userTagPool = t; });
    UserTagStore.allMap().then((m: Record<string, string[]>) => {
      this.userTagMap = m;
      if (this.filterTag !== '') {
        this.recompute();
      }
    });
  }

  // 预计算：按分类分组 + 当前标签筛选命中。仅在数据加载/标签切换时调用一次，build 直接读缓存。
  private recompute(): void {
    const d: AppData | null = this.data;
    if (!d) return;
    const g: ArticleGroup[] = [];
    for (let i: number = 0; i < d.tags.categories.length; i++) {
      const cat: string = d.tags.categories[i];
      g.push({ cat: cat, items: d.articles.filter((a: Article): boolean => a.category === cat) });
    }
    this.grouped = g;
    if (this.filterTag === '') {
      this.filteredArticles = d.articles;
      this.filteredQuestions = d.questions;
    } else {
      this.filteredArticles = d.articles.filter((a: Article): boolean => this.matchesFilter(a.id, a.tags));
      this.filteredQuestions = d.questions.filter((q: Question): boolean => this.matchesFilter(q.id, q.tags));
    }
    this.refreshLists();
  }

  // 同步分组/筛选结果到 LazyForEach 数据源
  private refreshLists(): void {
    this.groupDs.setData(this.grouped);
    this.articleDs.setData(this.filteredArticles);
    this.questionDs.setData(this.filteredQuestions);
  }

  // 判断是否命中当前标签筛选（自动标签或用户标签任一命中即可）
  private matchesFilter(id: string, tags: string[]): boolean {
    if (this.filterTag === '') return true;
    if (this.filterTag === '__mytags__') return (this.userTagMap[id]?.length ?? 0) > 0;
    const user: string[] = this.userTagMap[id] ?? [];
    return tags.includes(this.filterTag) || user.includes(this.filterTag);
  }

  // 响应个人中心的跳转意图：切换内部子标签，并按需应用「我的标记」筛选。
  // 关键：先刷新用户标记（详情页可能已新增/删除，aboutToAppear 的缓存已过期），
  // 再按最新数据 recompute，避免「有标记却筛选为空」。
  private applyNav(): void {
    this.tab = this.navSub === 'questions' ? 'questions' : 'articles';
    this.filterTag = this.navTag === '__mytags__' ? '__mytags__' : '';
    this.refreshUserTags();
  }

  // 顶部搜索 → 全文检索页（带 q，Search 页自动检索并高亮）
  private onSearch(): void {
    const params: SearchParam = { q: this.kw };
    this.pageStack.pushPathByName('Search', params);
  }

  // 分组标题
  @Builder groupHeader(title: string) {
    SectionTitle({ title: title })
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .width('100%')
      .padding({ top: SPACE.md })
  }

  // 列表行：图标 + 标题 + 副标题 + 标签 chips（最多 3 个）+ 箭头
  @Builder rowItem(title: string, sub: string, tags?: string[], isQuestion?: boolean) {
    Row() {
      IconTile({
        emoji: isQuestion ? '❓' : '📖',
        bg: isQuestion ? $r('app.color.accent_soft') : $r('app.color.brand_light'),
        fg: isQuestion ? $r('app.color.accent') : $r('app.color.brand'),
        dim: 44
      })
      .margin({ right: SPACE.md })
      Column() {
        Text(title)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(sub)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
          .width('100%')
        // 标签行：自动换行，最多展示前 3 个
        if (tags !== undefined && tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(tags.slice(0, 3), (t: string) => {
              Text(t)
                .fontSize(FONT.mini)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.xs, right: SPACE.xs })
            }, (t: string) => t)
            if (tags.length > 3) {
              Text('+' + (tags.length - 3))
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
  }

  @Builder articleList() {
    if (this.filterTag !== '' && this.filteredArticles.length === 0) {
      EmptyState({ emoji: '🔍', text: this.filterTag === '__mytags__' ? '还没有标记的知识点' : `没有命中「${this.filterTag}」的知识点` })
    } else {
      List() {
        if (this.filterTag === '') {
          // 未筛选：按分类分组（读预缓存 grouped）
          LazyForEach(this.groupDs, (g: ArticleGroup) => {
            ListItemGroup({ header: this.groupHeader(g.cat) }) {
              ForEach(g.items, (a: Article) => {
                ListItem() {
                  this.rowItem(a.title, '知识点', a.tags, false)
                }
                .onClick(() => {
                  const params: DetailParam = { id: a.id, kind: 'article' };
                  this.pageStack.pushPathByName('Detail', params);
                })
              }, (a: Article) => a.id)
            }
          }, (g: ArticleGroup) => g.cat)
        } else {
          // 筛选态：平铺命中项（读预缓存 filteredArticles）
          LazyForEach(this.articleDs, (a: Article) => {
            ListItem() {
              this.rowItem(a.title, a.category, a.tags, false)
            }
            .onClick(() => {
              const params: DetailParam = { id: a.id, kind: 'article' };
              this.pageStack.pushPathByName('Detail', params);
            })
          }, (a: Article) => a.id)
        }
      }
      .width('92%')
      .margin({ top: SPACE.sm })
    }
  }

  @Builder questionList() {
    if (this.filterTag !== '' && this.filteredQuestions.length === 0) {
      EmptyState({ emoji: '🔍', text: this.filterTag === '__mytags__' ? '还没有标记的真题' : `没有命中「${this.filterTag}」的真题` })
    } else {
      List() {
        LazyForEach(this.questionDs, (q: Question) => {
          ListItem() {
            this.rowItem(q.title, q.source, q.tags, true)
          }
          .onClick(() => {
            const params: DetailParam = { id: q.id, kind: 'question' };
            this.pageStack.pushPathByName('Detail', params);
          })
        }, (q: Question) => q.id)
      }
      .width('92%')
      .margin({ top: SPACE.sm })
    }
  }

  // 用户标签筛选条（横向滚动）：点击按标签过滤列表
  @Builder tagFilterBar() {
    Scroll() {
      Row() {
        TagChip({ text: '🏷 我的标记', selected: this.filterTag === '__mytags__', onTap: () => { this.filterTag = '__mytags__'; this.recompute(); } })
          .margin({ right: SPACE.xs })
        TagChip({ text: '全部', selected: this.filterTag === '', onTap: () => { this.filterTag = ''; this.recompute(); } })
          .margin({ right: SPACE.xs })
        ForEach(this.userTagPool, (t: string) => {
          TagChip({ text: t, selected: this.filterTag === t, onTap: () => { this.filterTag = t; this.recompute(); } })
            .margin({ right: SPACE.xs })
        }, (t: string) => t)
      }
      .padding({ left: SPACE.lg, right: SPACE.lg })
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
    .margin({ bottom: SPACE.sm })
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 品牌头部
      PageHeader({ title: '素材' })

      // 顶部搜索框（胶囊形 + x 清空 + 右侧搜索按钮，跳全文检索页）
      Row() {
        Row() {
          TextInput({ placeholder: '搜索知识点 / 真题', text: this.kw })
            .onChange((v: string) => {
              this.kw = v;
            })
            .onSubmit(() => this.onSearch())
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.transparent'))
            .borderRadius(RADIUS.pill)
            .padding({ left: 0, right: 4 })
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
        .layoutWeight(1)
        .height(40)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.pill)
        .padding({ left: 14, right: 6 })
        Button('搜索')
          .onClick(() => this.onSearch())
          .height(40)
          .margin({ left: 8 })
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .borderRadius(RADIUS.pill)
      }
      .width('92%')
      .margin({ bottom: SPACE.sm })

      // 用户标签筛选条：有标记、或当前处于筛选态时显示，
      // 保证「我的标记」筛选下始终能点「全部」清除，不会卡成空列表死胡同
      if (this.userTagPool.length > 0 || this.filterTag !== '') {
        this.tagFilterBar()
      }

      if (this.data) {
        Tabs({ index: this.tab === 'questions' ? 1 : 0, barPosition: BarPosition.Start }) {
          TabContent() {
            this.articleList()
          }.tabBar('知识点')

          TabContent() {
            this.questionList()
          }.tabBar('真题库')
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        EmptyState({ emoji: '⏳', text: '加载中…' })
      }
    }
  .width('100%')
  .height('100%')
  .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
  .padding({ top: this.safeTop, bottom: 100 + this.safeBottom })
  // 底部预留 100vp 悬浮 Tab 栏空间（高度 56 + 顶部 8 + 底部 28 + 自身 safeBottom），
  // 避免内部 List 最后一行被悬浮 Tab 栏遮挡
  }
}

// 预览专用：使用 mock 素材数据，Previewer 无需 DataStore/router
@Preview
@Component
struct CategoryPreview {
  build() {
    Column() {
      Row() {
        Text('素材')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: SPACE.lg, top: SPACE.md, bottom: SPACE.sm })

      Column() {
        Text('考情')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: SPACE.sm })
        Column() {
          Text('鹤壁市面试考情速览')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 4 })
          Text('结构化面试 · 3 道题 · 共 15 分钟')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding(SPACE.md)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.md)
      }
      .width('100%')
      .padding({ left: SPACE.lg, right: SPACE.lg })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding(16)
  }
}

// 素材 Tab：对应原「分类浏览」内容（知识点 / 真题库），顶部搜索框 → 全文检索
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { UserTagStore } from '../utils/UserTagStore';
import { FONT, RADIUS, SPACE } from '../utils/Theme';

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

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d) => {
      this.data = d;
      this.recompute();   // 数据就绪后预计算分组与筛选结果
    });
    UserTagStore.allTags().then((t) => { this.userTagPool = t; });
    UserTagStore.allMap().then((m) => { this.userTagMap = m; });
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
  }

  // 判断是否命中当前标签筛选（自动标签或用户标签任一命中即可）
  // 拆成 id/tags 两个基本参数，避免结构化类型 / any/unknown 的 strict 冲突
  private matchesFilter(id: string, tags: string[]): boolean {
    if (this.filterTag === '') return true;
    const user: string[] = this.userTagMap[id] ?? [];
    return tags.includes(this.filterTag) || user.includes(this.filterTag);
  }

  // 顶部搜索 → 全文检索页
  private onSearch(): void {
    if (this.kw.trim()) {
      router.pushUrl({ url: 'pages/Search', params: { 'q': this.kw } });
    }
  }

  @Builder groupHeader(title: string) {
    Text(title)
      .fontSize(FONT.body)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_title'))
      .backgroundColor($r('app.color.background'))
      .width('100%')
      .padding({ top: SPACE.md, bottom: SPACE.sm })
  }

  // 列表行：标题 + 副标题 + 标签 chips（最多 3 个，超出显示 +N）
  @Builder rowItem(title: string, sub: string, tags?: string[]) {
    Row() {
      Column() {
        Text(title)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(sub)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
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
  }

  @Builder articleList() {
    if (this.filterTag !== '' && this.filteredArticles.length === 0) {
      // 筛选态无结果：空态提示
      Text(`没有命中「${this.filterTag}」的知识点`)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: SPACE.xl })
    } else {
      List() {
        if (this.filterTag === '') {
          // 未筛选：按分类分组（读预缓存 grouped）
          ForEach(this.grouped, (g: ArticleGroup) => {
            ListItemGroup({ header: this.groupHeader(g.cat) }) {
              ForEach(g.items, (a: Article) => {
                ListItem() {
                  this.rowItem(a.title, '知识点', a.tags)
                }
                .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: a.id, kind: 'article' } }))
              }, (a: Article) => a.id)
            }
          }, (g: ArticleGroup) => g.cat)
        } else {
          // 筛选态：平铺命中项（读预缓存 filteredArticles）
          ForEach(this.filteredArticles, (a: Article) => {
            ListItem() {
              this.rowItem(a.title, a.category, a.tags)
            }
            .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: a.id, kind: 'article' } }))
          }, (a: Article) => a.id)
        }
      }
      .width('92%')
      .margin({ top: SPACE.sm })
    }
  }

  @Builder questionList() {
    if (this.filterTag !== '' && this.filteredQuestions.length === 0) {
      Text(`没有命中「${this.filterTag}」的真题`)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: SPACE.xl })
    } else {
      List() {
        // 读预缓存 filteredQuestions（'' 时=全部）
        ForEach(this.filteredQuestions, (q: Question) => {
          ListItem() {
            this.rowItem(q.title, q.source, q.tags)
          }
          .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: q.id, kind: 'question' } }))
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
        Text('全部')
          .fontSize(FONT.caption)
          .fontColor(this.filterTag === '' ? $r('app.color.on_primary') : $r('app.color.brand'))
          .backgroundColor(this.filterTag === '' ? $r('app.color.brand') : $r('app.color.tag_bg'))
          .borderRadius(RADIUS.pill)
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.xs, bottom: SPACE.xs })
          .margin({ right: SPACE.xs })
          .onClick(() => { this.filterTag = ''; this.recompute(); })
        ForEach(this.userTagPool, (t: string) => {
          Text(t)
            .fontSize(FONT.caption)
            .fontColor(this.filterTag === t ? $r('app.color.on_primary') : $r('app.color.brand'))
            .backgroundColor(this.filterTag === t ? $r('app.color.brand') : $r('app.color.tag_bg'))
            .borderRadius(RADIUS.pill)
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.xs, bottom: SPACE.xs })
            .margin({ right: SPACE.xs })
            .onClick(() => { this.filterTag = t; this.recompute(); })
        }, (t: string) => t)
      }
      .padding({ left: SPACE.lg, right: SPACE.lg })
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
    .margin({ bottom: SPACE.sm })
  }

  build() {
    Column() {
      // 顶部搜索框（对应全文检索功能）
      Row() {
        TextInput({ placeholder: '搜索知识点 / 真题，进入全文检索', text: this.kw })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: SPACE.lg })
          .onChange((v: string) => {
            this.kw = v;
          })
          .onSubmit(() => this.onSearch())
        if (this.kw.trim()) {
          Text('搜索')
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.brand'))
            .padding({ left: SPACE.sm, right: SPACE.xs })
            .onClick(() => this.onSearch())
        }
      }
      .width('92%')
      .margin({ top: SPACE.lg, bottom: SPACE.sm })

      // 用户标签筛选条（仅当用户已打过标记时显示）
      if (this.userTagPool.length > 0) {
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
        Text('加载中…')
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.text_secondary'))
          .margin(SPACE.xl)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

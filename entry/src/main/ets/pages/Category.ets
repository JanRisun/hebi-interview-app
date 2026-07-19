// 素材 Tab：对应原「分类浏览」内容（知识点 / 真题库），顶部搜索框 → 全文检索
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { UserTagStore } from '../utils/UserTagStore';
import { FONT, RADIUS, SPACE } from '../utils/Theme';

@Component
export struct CategoryView {
  @State data: AppData | null = null;
  @State tab: string = 'articles';
  @State kw: string = '';   // 顶部搜索框内容
  @State filterTag: string = '';                       // 当前选中的用户标签筛选（''=不过滤）
  @State userTagPool: string[] = [];                   // 全部用户标签（用于筛选条）
  @State userTagMap: Record<string, string[]> = {};    // 内容id→用户标签（用于命中判断）

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d) => {
      this.data = d;
    });
    UserTagStore.allTags().then((t) => { this.userTagPool = t; });
    UserTagStore.allMap().then((m) => { this.userTagMap = m; });
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
    List() {
      if (this.filterTag === '') {
        // 未筛选：按分类分组
        ForEach(this.data!.tags.categories, (cat: string) => {
          ListItemGroup({ header: this.groupHeader(cat) }) {
            ForEach(this.data!.articles.filter((a) => a.category === cat), (a: Article) => {
              ListItem() {
                this.rowItem(a.title, '知识点', a.tags)
              }
              .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: a.id, kind: 'article' } }))
            }, (a: Article) => a.id)
          }
        }, (cat: string) => cat)
      } else {
        // 筛选态：平铺命中项，副标题显示所属分类
        ForEach(this.data!.articles.filter((a) => this.matchesFilter(a.id, a.tags)), (a: Article) => {
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

  @Builder questionList() {
    List() {
      ForEach(this.data!.questions.filter((q) => this.matchesFilter(q.id, q.tags)), (q: Question) => {
        ListItem() {
          this.rowItem(q.title, q.source, q.tags)
        }
        .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: q.id, kind: 'question' } }))
      }, (q: Question) => q.id)
    }
    .width('92%')
    .margin({ top: SPACE.sm })
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
          .onClick(() => { this.filterTag = ''; })
        ForEach(this.userTagPool, (t: string) => {
          Text(t)
            .fontSize(FONT.caption)
            .fontColor(this.filterTag === t ? $r('app.color.on_primary') : $r('app.color.brand'))
            .backgroundColor(this.filterTag === t ? $r('app.color.brand') : $r('app.color.tag_bg'))
            .borderRadius(RADIUS.pill)
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.xs, bottom: SPACE.xs })
            .margin({ right: SPACE.xs })
            .onClick(() => { this.filterTag = t; })
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

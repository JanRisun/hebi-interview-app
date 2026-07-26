import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { BackHeader } from '../utils/BackHeader';
import { LazyDataSource } from '../utils/LazySource';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile, EmptyState, HighlightText } from '../utils/Ui';

// 导航参数透传对象（规避 arkts-no-untyped-obj-literals）
interface DetailParam { id: string; kind: string; cat?: string }

interface FavItem {
  id: string;
  kind: string;      // 'article' | 'question'
  title: string;
  sub: string;       // 知识点=分类，真题=来源
}

// 顶部类型筛选（区分知识库收藏 / 题目收藏）
interface KindFilter { label: string; kind: string }

@Component
export struct Favorites {
  @State items: FavItem[] = [];
  @State kw: string = '';                       // 搜索关键词
  @State filterKind: string = 'all';            // 类型筛选：all / article / question
  // 数据源刷新靠 IDataSource 的 onDataReloaded 通知，无需 @State（@State 代理会破坏私有字段）
  ds: LazyDataSource<FavItem> = new LazyDataSource<FavItem>([]);
  @Consume pageStack: NavPathStack;

  private readonly filters: KindFilter[] = [
    { label: '全部', kind: 'all' },
    { label: '知识点', kind: 'article' },
    { label: '真题', kind: 'question' }
  ];

  // 订阅全局收藏/标签版本号：详情页加收藏后自动重读，无需重启 app
  @StorageLink('favTagVersion') @Watch('onDataChange') tagVersion: number = 0;

  aboutToAppear(): void {
    this.refreshData();
  }

  // 收藏/标签变更时触发（@Watch）：重读最新收藏列表
  private onDataChange(): void {
    this.refreshData();
  }

  private refreshData(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then(async () => {
      const ids: string[] = await FavStore.getIds();
      const list: FavItem[] = [];
      const d: AppData = DataStore.data;
      ids.forEach((id) => {
        const a: Article | undefined = d.articles.find((x) => x.id === id);
        if (a) {
          list.push({ id, kind: 'article', title: a.title, sub: a.category });
          return;
        }
        const q: Question | undefined = d.questions.find((x) => x.id === id);
        if (q) {
          list.push({ id, kind: 'question', title: q.title, sub: q.source });
        }
      });
      this.items = list;
      this.refresh();
    });
  }

  // 同步过滤结果到 LazyForEach 数据源（先按类型筛选，再按关键词过滤）
  private refresh(): void {
    this.ds.setData(this.filtered());
  }

  // 类型筛选 + 关键词过滤（标题 / 来源 / 分类）
  private filtered(): FavItem[] {
    let list: FavItem[] = this.items;
    if (this.filterKind !== 'all') {
      list = list.filter((it: FavItem): boolean => it.kind === this.filterKind);
    }
    const k: string = this.kw.trim().toLowerCase();
    if (!k) {
      return list;
    }
    return list.filter((it: FavItem): boolean =>
      it.title.toLowerCase().includes(k) || it.sub.toLowerCase().includes(k));
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  // 列表行：彩色图标 + 标题（高亮）+ 类型徽标 + 副标题（高亮）+ 箭头
  @Builder rowItem(it: FavItem) {
    Row() {
      IconTile({
        emoji: it.kind === 'article' ? '📖' : '❓',
        bg: it.kind === 'article' ? $r('app.color.brand_light') : $r('app.color.accent_soft'),
        fg: it.kind === 'article' ? $r('app.color.brand') : $r('app.color.accent'),
        dim: 44
      })
        .margin({ right: SPACE.md })
      Column() {
        HighlightText({ text: it.title, kw: this.kw, fontSize: FONT.body, baseColor: $r('app.color.text_primary'), hitColor: $r('app.color.brand'), singleLine: true })
          .width('100%')
        Row() {
          // 类型徽标：明确区分「知识点」与「真题」
          Text(it.kind === 'article' ? '知识点' : '真题')
            .fontSize(FONT.mini)
            .fontColor(it.kind === 'article' ? $r('app.color.brand') : $r('app.color.accent'))
            .backgroundColor(it.kind === 'article' ? $r('app.color.brand_light') : $r('app.color.accent_soft'))
            .borderRadius(RADIUS.sm)
            .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
            .margin({ right: SPACE.sm })
          HighlightText({ text: it.sub, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), hitColor: $r('app.color.brand'), singleLine: true })
            .layoutWeight(1)
        }
        .margin({ top: SPACE.xs })
        .width('100%')
        .alignItems(VerticalAlign.Center)
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
    .onClick(() => {
      const params: DetailParam = { id: it.id, kind: it.kind, cat: it.sub };
      this.pageStack.pushPathByName('Detail', params);
    })
  }

  build() {
    Column() {
      BackHeader({ title: '我的收藏' })

      // 顶部搜索框（胶囊形 + 搜索图标 + 清空按钮），输入即实时检索
      Row() {
        Text('🔍')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: SPACE.md, right: SPACE.sm })
        TextInput({ placeholder: '搜索收藏的标题或来源', text: this.kw })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.transparent'))
          .padding({ left: SPACE.sm })
          .onChange((v: string) => {
            this.kw = v;
            this.refresh();
          })
        if (this.kw) {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(18)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ right: SPACE.md })
            .onClick(() => {
              this.kw = '';
              this.refresh();
            })
        }
      }
      .width('92%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.pill)
      .margin({ bottom: SPACE.sm })
      .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })

      // 类型筛选：区分知识库收藏 / 题目收藏
      Row() {
        ForEach(this.filters, (f: KindFilter) => {
          Text(f.label)
            .fontSize(FONT.caption)
            .fontColor(this.filterKind === f.kind ? $r('app.color.on_primary') : $r('app.color.text_primary'))
            .backgroundColor(this.filterKind === f.kind ? $r('app.color.brand') : $r('app.color.surface'))
            .borderRadius(RADIUS.sm)
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
            .margin({ right: SPACE.sm })
            .onClick(() => {
              this.filterKind = f.kind;
              this.refresh();
            })
        }, (f: KindFilter) => f.label)
      }
      .width('92%')
      .margin({ bottom: SPACE.sm })
      .justifyContent(FlexAlign.Start)

      if (this.items.length === 0) {
        EmptyState({ emoji: '🤍', text: '还没有收藏，去详情页点击 ☆ 收藏吧' })
      } else if (this.filtered().length === 0) {
        EmptyState({ emoji: '🔍', text: this.kw.trim()
          ? `没有匹配「${this.kw.trim()}」的收藏`
          : (this.filterKind === 'article' ? '还没有收藏的知识点' : this.filterKind === 'question' ? '还没有收藏的真题' : '该分类下还没有收藏') })
      } else {
        List() {
          LazyForEach(this.ds, (it: FavItem) => {
            ListItem() {
              this.rowItem(it)
            }
          }, (it: FavItem) => it.id)
        }
        .width('92%')
        .layoutWeight(1)
        .alignSelf(ItemAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      // 我的收藏是整屏 NavDestination，进入后首页悬浮 Tab 栏已隐藏，底部只留系统安全区
      .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

// 预览专用：mock 收藏列表，Previewer 无需 FavStore
@Preview
@Component
struct FavoritesPreview {
  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
        Text('我的收藏')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 12 })
      }
      .width('100%')
      .padding(SPACE.lg)

      Row() {
        Text('🔍')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: SPACE.md, right: SPACE.sm })
        Text('搜索收藏内容')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('90%')
      .height(40)
      .padding({ left: 12 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.pill)
      .margin({ top: SPACE.sm })

      Row() {
        Text('全部')
          .fontSize(13)
          .fontColor($r('app.color.on_primary'))
          .backgroundColor($r('app.color.brand'))
          .borderRadius(RADIUS.sm)
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
          .margin({ right: SPACE.sm })
        Text('知识点')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.sm)
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
          .margin({ right: SPACE.sm })
        Text('真题')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.sm)
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
      }
      .width('90%')
      .margin({ top: SPACE.sm })

      Column() {
        Row() {
          Text('📖')
            .fontSize(20)
            .margin({ right: 12 })
          Column() {
            Text('综合分析类答题框架')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Row() {
              Text('知识点')
                .fontSize(11)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ right: SPACE.sm })
              Text('考情')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .margin({ top: 2 })
            .alignItems(VerticalAlign.Center)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('›')
            .fontSize(20)
            .fontColor($r('app.color.text_arrow'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('90%')
      .padding(SPACE.md)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.md)
      .margin({ top: SPACE.md })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding({ top: 16 })
  }
}

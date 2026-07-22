import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { BackHeader } from '../utils/BackHeader';
import { LazyDataSource } from '../utils/LazySource';
import { RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile, EmptyState } from '../utils/Ui';

// 导航参数透传对象（规避 arkts-no-untyped-obj-literals）
interface DetailParam { id: string; kind: string }

interface FavItem {
  id: string;
  kind: string;
  title: string;
  sub: string;
}

@Component
export struct Favorites {
  @State items: FavItem[] = [];
  @State kw: string = '';   // 搜索关键词
  // 数据源刷新靠 IDataSource 的 onDataReloaded 通知，无需 @State（@State 代理会破坏私有字段）
  ds: LazyDataSource<FavItem> = new LazyDataSource<FavItem>([]);
  @Consume pageStack: NavPathStack;

  aboutToAppear(): void {
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

  // 同步过滤结果到 LazyForEach 数据源
  private refresh(): void {
    this.ds.setData(this.filterFavs());
  }

  // 按标题或来源/分类过滤收藏
  private filterFavs(): FavItem[] {
    const k: string = this.kw.trim().toLowerCase();
    if (!k) {
      return this.items;
    }
    const out: FavItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const it: FavItem = this.items[i];
      if (it.title.toLowerCase().includes(k) || it.sub.toLowerCase().includes(k)) {
        out.push(it);
      }
    }
    return out;
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      BackHeader({ title: '我的收藏' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索收藏的标题或来源', text: this.kw })
          .onChange((v: string) => {
            this.kw = v;
            this.refresh();
          })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: 14 })
      }
      .width('92%')
      .margin({ bottom: 10 })

      if (this.items.length === 0) {
        EmptyState({ emoji: '🤍', text: '还没有收藏，去详情页点击 ☆ 收藏吧' })
      } else if (this.filterFavs().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw}」的收藏` })
      } else {
        List() {
          LazyForEach(this.ds, (it: FavItem) => {
            ListItem() {
              Row() {
                IconTile({
                  emoji: it.kind === 'article' ? '📖' : '❓',
                  bg: it.kind === 'article' ? $r('app.color.brand_light') : $r('app.color.accent_soft'),
                  fg: it.kind === 'article' ? $r('app.color.brand') : $r('app.color.accent'),
                  dim: 40
                })
                  .margin({ right: 12 })
                Column() {
                  Text(it.title)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${it.kind === 'article' ? '知识点' : '真题'} · ${it.sub}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 3 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text('›')
                  .fontSize(20)
                  .fontColor($r('app.color.text_arrow'))
              }
              .width('100%')
              .padding(14)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(RADIUS.md)
              .margin({ bottom: 8 })
              .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
              .onClick(() => {
                const params: DetailParam = { id: it.id, kind: it.kind };
                this.pageStack.pushPathByName('Detail', params);
              })
            }
          }, (it: FavItem) => it.id)
        }
        .width('92%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
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
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
        Text('搜索收藏内容')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8 })
      }
      .width('90%')
      .height(40)
      .padding({ left: 12 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.pill)

      Column() {
        Row() {
          Text('⭐')
            .fontSize(20)
            .margin({ right: 12 })
          Column() {
            Text('综合分析类答题框架')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text('考情')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
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

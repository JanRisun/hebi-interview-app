import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, SearchHit } from '../model/Types';
import { searchAll } from '../model/SearchEngine';
import { LazyDataSource } from '../utils/LazySource';
import { RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { IconTile, EmptyState, TagChip, HighlightText } from '../utils/Ui';

// 导航参数透传对象（规避 arkts-no-untyped-obj-literals）
interface DetailParam { id: string; kind: string; kw?: string }

@Component
export struct SearchPage {
  @State data: AppData | null = null;
  @State kw: string = '';
  @State hits: SearchHit[] = [];
  // 数据源刷新靠 IDataSource 的 onDataReloaded 通知，无需 @State（@State 代理会破坏私有字段）
  ds: LazyDataSource<SearchHit> = new LazyDataSource<SearchHit>([]);
  @Prop params: Object;                    // 路由参数：{ q }（Navigation 经 routeMap 透传）
  @Consume pageStack: NavPathStack;

  aboutToAppear(): void {
    // 支持从顶部搜索框带 q 参数进入，自动检索
    const p = (this.params ?? {}) as Record<string, Object>;
    const q: string = (p['q'] ? (p['q'] as string) : '');
    DataStore.load(getContext(this) as common.UIAbilityContext).then((d) => {
      this.data = d;
      if (q) {
        this.kw = q;
        this.doSearch();
      }
    });
  }

  doSearch(): void {
    if (this.data && this.kw.trim()) {
      this.hits = searchAll(this.data, this.kw);
    } else {
      this.hits = [];
    }
    this.ds.setData(this.hits);
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      BackHeader({ title: '搜索' })

      Row() {
        Row() {
          TextInput({ placeholder: '输入关键词，如：调研、红旗渠、情景模拟', text: this.kw })
            .onChange((v: string) => {
              this.kw = v;
            })
            .onSubmit(() => this.doSearch())
            .layoutWeight(1)
            .height(40)
            .backgroundColor(Color.Transparent)
            .borderRadius(RADIUS.pill)
            .padding({ left: 0, right: 4 })
          if (this.kw) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ right: SPACE.md })
              .onClick(() => {
                this.kw = '';
                this.doSearch();
              })
          }
        }
        .layoutWeight(1)
        .height(40)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.pill)
        .padding({ left: 14, right: 6 })
        Button('搜索')
          .onClick(() => this.doSearch())
          .height(40)
          .margin({ left: 8 })
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .borderRadius(RADIUS.pill)
      }
      .width('92%')
      .margin({ bottom: 10 })

      if (this.data) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.tags.keywords.slice(0, 14), (k: string) => {
            TagChip({ text: k, selected: false, onTap: (): void => { this.kw = k; this.doSearch(); } })
              .margin(4)
          }, (k: string) => k)
        }
        .width('92%')
      }

      if (this.hits.length === 0) {
        EmptyState({ emoji: '🔍', text: this.kw ? `没有匹配「${this.kw}」的结果` : '输入关键词开始搜索' })
      } else {
        List() {
          LazyForEach(this.ds, (h: SearchHit) => {
            ListItem() {
              Row() {
                IconTile({
                  emoji: h.kind === 'article' ? '📖' : '❓',
                  bg: h.kind === 'article' ? $r('app.color.brand_light') : $r('app.color.accent_soft'),
                  fg: h.kind === 'article' ? $r('app.color.brand') : $r('app.color.accent'),
                  dim: 40
                })
                  .margin({ right: 12 })
                Column() {
                  HighlightText({
                    text: h.title,
                    kw: this.kw,
                    fontSize: 15,
                    baseColor: $r('app.color.text_primary'),
                    hitColor: $r('app.color.brand')
                  })
                    .margin({ bottom: 4 })
                  HighlightText({
                    text: `${h.kind === 'article' ? '知识点' : '真题'} · ${h.category}`,
                    kw: this.kw,
                    fontSize: 12,
                    baseColor: $r('app.color.text_secondary'),
                    hitColor: $r('app.color.brand')
                  })
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
                const params: DetailParam = { id: h.id, kind: h.kind, kw: this.kw };
                this.pageStack.pushPathByName('Detail', params);
              })
            }
          }, (h: SearchHit) => h.id)
        }
        .width('92%')
        .layoutWeight(1)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: this.safeBottom + 12 })
  }
}

// 预览专用：mock 搜索结果，Previewer 无需 DataStore/router
@Preview
@Component
struct SearchPreview {
  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
          .margin({ right: 12 })
        Row() {
          Text('🔍')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
          Text('综合分析')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 12 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.pill)
      }
      .width('100%')
      .padding(SPACE.lg)

      Column() {
        Text('📰')
          .fontSize(16)
          .margin({ right: 10 })
        Column() {
          Text('综合分析类答题框架')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('考情 · 知识点')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('90%')
      .padding(SPACE.md)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.md)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding({ top: 16 })
  }
}

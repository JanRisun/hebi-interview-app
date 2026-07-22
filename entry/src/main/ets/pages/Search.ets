import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, SearchHit } from '../model/Types';
import { searchAll } from '../model/SearchEngine';
import { RADIUS } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { IconTile, EmptyState, TagChip } from '../utils/Ui';

@Entry
@Component
struct SearchPage {
  @State data: AppData | null = null;
  @State kw: string = '';
  @State hits: SearchHit[] = [];

  aboutToAppear(): void {
    // 支持从顶部搜索框带 q 参数进入，自动检索
    const p = router.getParams() as Record<string, Object> | undefined;
    const q: string = (p && p['q']) ? (p['q'] as string) : '';
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
  }

  build() {
    Column() {
      BackHeader({ title: '搜索' })

      Row() {
        TextInput({ placeholder: '输入关键词，如：调研、红旗渠、情景模拟', text: this.kw })
          .onChange((v: string) => {
            this.kw = v;
          })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: 14 })
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
          ForEach(this.hits, (h: SearchHit) => {
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
                  Text(h.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text(`${h.kind === 'article' ? '知识点' : '真题'} · ${h.category}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
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
                router.pushUrl({ url: 'pages/Detail', params: { id: h.id, kind: h.kind } });
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
  }
}

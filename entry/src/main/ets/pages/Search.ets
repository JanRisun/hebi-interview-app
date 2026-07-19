import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, SearchHit } from '../model/Types';
import { searchAll } from '../model/SearchEngine';

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
      Row() {
        TextInput({ placeholder: '输入关键词，如：调研、红旗渠、情景模拟', text: this.kw })
          .onChange((v: string) => {
            this.kw = v;
          })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .padding({ left: 14 })
        Button('搜索')
          .onClick(() => this.doSearch())
          .height(40)
          .margin({ left: 8 })
          .backgroundColor('#185FA5')
      }
      .width('92%')
      .margin({ top: 12, bottom: 10 })

      if (this.data) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.tags.keywords.slice(0, 14), (k: string) => {
            Text(k)
              .fontSize(12)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .backgroundColor('#E6F1FB')
              .fontColor('#185FA5')
              .borderRadius(14)
              .margin(4)
              .onClick(() => {
                this.kw = k;
                this.doSearch();
              })
          }, (k: string) => k)
        }
        .width('92%')
      }

      List() {
        ForEach(this.hits, (h: SearchHit) => {
          ListItem() {
            Row() {
              Column() {
                Text(h.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1f2d3d')
                Text(`${h.kind === 'article' ? '知识点' : '真题'} · ${h.category}`)
                  .fontSize(12)
                  .fontColor('#888')
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text('›')
                .fontSize(20)
                .fontColor('#CCC')
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(10)
            .margin({ bottom: 8 })
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
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

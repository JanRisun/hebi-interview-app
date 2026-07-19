import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { BackHeader } from '../utils/BackHeader';

interface FavItem {
  id: string;
  kind: string;
  title: string;
  sub: string;
}

@Entry
@Component
struct Favorites {
  @State items: FavItem[] = [];
  @State kw: string = '';   // 搜索关键词

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
    });
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

  build() {
    Column() {
      // 返回按钮 + 标题
      BackHeader({ title: '我的收藏' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索收藏的标题或来源', text: this.kw })
          .onChange((v: string) => {
            this.kw = v;
          })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .padding({ left: 14 })
      }
      .width('92%')
      .margin({ bottom: 10 })

      if (this.items.length === 0) {
        Text('还没有收藏，去详情页点击 ☆ 收藏吧')
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else if (this.filterFavs().length === 0) {
        Text(`没有匹配「${this.kw}」的收藏`)
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else {
        List() {
          ForEach(this.filterFavs(), (it: FavItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(it.title)
                    .fontSize(15)
                    .fontColor('#1f2d3d')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${it.kind === 'article' ? '知识点' : '真题'} · ${it.sub}`)
                    .fontSize(12)
                    .fontColor('#888')
                    .margin({ top: 3 })
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
              .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: it.id, kind: it.kind } }))
            }
          }, (it: FavItem) => it.id)
        }
        .width('92%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

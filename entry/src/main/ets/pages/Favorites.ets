import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { BackHeader } from '../utils/BackHeader';
import { RADIUS } from '../utils/Theme';
import { IconTile, EmptyState } from '../utils/Ui';

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
      BackHeader({ title: '我的收藏' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索收藏的标题或来源', text: this.kw })
          .onChange((v: string) => {
            this.kw = v;
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
          ForEach(this.filterFavs(), (it: FavItem) => {
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
    .backgroundColor($r('app.color.background'))
  }
}

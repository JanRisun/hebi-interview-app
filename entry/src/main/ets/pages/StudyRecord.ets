// 我的学习记录：从本地 prefs 读取逐题自评结果，支持搜索
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, Question, RatedItem } from '../model/Types';
import { BackHeader } from '../utils/BackHeader';

const PREF_NAME: string = 'practice';

@Entry
@Component
struct StudyRecord {
  @State rated: RatedItem[] = [];
  @State kw: string = '';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d: AppData) => {
      preferences.getPreferences(ctx, PREF_NAME).then((p: preferences.Preferences) => {
        const rIds: string = p.getSync('r_ids', '') as string;
        const list: RatedItem[] = [];
        if (rIds) {
          const arr: string[] = rIds.split(',');
          for (let i = 0; i < arr.length; i++) {
            const id: string = arr[i];
            const rating: string = p.getSync('r_' + id, '') as string;
            const q: Question | undefined = DataStore.questionById(id);
            list.push({ id: id, title: q ? q.title : id, rating: rating });
          }
        }
        this.rated = list;
      });
    });
  }

  // 按题目标题过滤
  private filterRated(): RatedItem[] {
    const k: string = this.kw.trim().toLowerCase();
    if (!k) {
      return this.rated;
    }
    const out: RatedItem[] = [];
    for (let i = 0; i < this.rated.length; i++) {
      if (this.rated[i].title.toLowerCase().includes(k)) {
        out.push(this.rated[i]);
      }
    }
    return out;
  }

  private rateColor(r: string): string {
    if (r === '掌握') return '#1a7f37';
    if (r === '模糊') return '#b8860b';
    if (r === '不会') return '#c0392b';
    return '#999';
  }

  build() {
    Column() {
      BackHeader({ title: '我的学习记录' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索自评过的题目', text: this.kw })
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

      if (this.rated.length === 0) {
        Text('还没有自评记录，去真题模考练一套吧')
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else if (this.filterRated().length === 0) {
        Text(`没有匹配「${this.kw}」的记录`)
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else {
        List() {
          ForEach(this.filterRated(), (r: RatedItem) => {
            ListItem() {
              Row() {
                Text(r.title)
                  .fontSize(14)
                  .fontColor('#1f2d3d')
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(r.rating)
                  .fontSize(12)
                  .fontColor(this.rateColor(r.rating))
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .margin({ bottom: 6 })
              .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: r.id, kind: 'question' } }))
            }
          }, (r: RatedItem): string => r.id)
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

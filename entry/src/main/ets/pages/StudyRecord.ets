// 我的学习记录：从本地 prefs 读取逐题自评结果，支持搜索
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, Question, RatedItem } from '../model/Types';
import { BackHeader } from '../utils/BackHeader';
import { RADIUS } from '../utils/Theme';
import { IconTile, EmptyState } from '../utils/Ui';

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
          for (let i: number = 0; i < arr.length; i++) {
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
    for (let i: number = 0; i < this.rated.length; i++) {
      if (this.rated[i].title.toLowerCase().includes(k)) {
        out.push(this.rated[i]);
      }
    }
    return out;
  }

  // 评级颜色随深浅模式切换
  private rateColor(r: string): ResourceColor {
    if (r === '掌握') return $r('app.color.success');
    if (r === '模糊') return $r('app.color.warning');
    if (r === '不会') return $r('app.color.danger');
    return $r('app.color.text_tertiary');
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
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: 14 })
      }
      .width('92%')
      .margin({ bottom: 10 })

      if (this.rated.length === 0) {
        EmptyState({ emoji: '📝', text: '还没有自评记录，去真题模考练一套吧' })
      } else if (this.filterRated().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw}」的记录` })
      } else {
        List() {
          ForEach(this.filterRated(), (r: RatedItem) => {
            ListItem() {
              Row() {
                IconTile({ emoji: '📝', bg: $r('app.color.brand_light'), fg: $r('app.color.brand'), dim: 40 })
                  .margin({ right: 12 })
                Text(r.title)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(r.rating)
                  .fontSize(12)
                  .fontColor(this.rateColor(r.rating))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(RADIUS.sm)
              .margin({ bottom: 6 })
              .shadow({ radius: 8, color: $r('app.color.card_stroke'), offsetY: 2 })
              .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: r.id, kind: 'question' } }))
            }
          }, (r: RatedItem) => r.id)
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

// 我的学习记录：从本地 prefs 读取逐题自评结果，支持搜索
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, Question, RatedItem } from '../model/Types';
import { BackHeader } from '../utils/BackHeader';
import { LazyDataSource } from '../utils/LazySource';
import { RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile, EmptyState } from '../utils/Ui';

// 导航参数透传对象（规避 arkts-no-untyped-obj-literals）
interface DetailParam { id: string; kind: string }

const PREF_NAME: string = 'practice';

@Component
export struct StudyRecord {
  @State rated: RatedItem[] = [];
  @State kw: string = '';
  // 数据源刷新靠 IDataSource 的 onDataReloaded 通知，无需 @State（@State 代理会破坏私有字段）
  ds: LazyDataSource<RatedItem> = new LazyDataSource<RatedItem>([]);
  @Consume pageStack: NavPathStack;

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
        this.refresh();
      });
    });
  }

  // 同步过滤结果到 LazyForEach 数据源
  private refresh(): void {
    this.ds.setData(this.filterRated());
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

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      BackHeader({ title: '我的学习记录' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索自评过的题目', text: this.kw })
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

      if (this.rated.length === 0) {
        EmptyState({ emoji: '📝', text: '还没有自评记录，去真题模考练一套吧' })
      } else if (this.filterRated().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw}」的记录` })
      } else {
        List() {
          LazyForEach(this.ds, (r: RatedItem) => {
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
              .onClick(() => {
                const params: DetailParam = { id: r.id, kind: 'question' };
                this.pageStack.pushPathByName('Detail', params);
              })
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
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

// 预览专用：mock 学习记录，Previewer 无需 prefs
@Preview
@Component
struct StudyRecordPreview {
  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
        Text('学习记录')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 12 })
      }
      .width('100%')
      .padding(SPACE.lg)

      Column() {
        Row() {
          Column() {
            Text('谈谈你对"躺平"现象的看法')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('掌握')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#2DBE60')
            .borderRadius(RADIUS.pill)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
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

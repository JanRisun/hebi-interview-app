// 我的真题演练记录：从本地 prefs 读取每套模考结果，支持搜索
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, PracticeSession } from '../model/Types';
import { BackHeader } from '../utils/BackHeader';
import { LazyDataSource } from '../utils/LazySource';
import { RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile, EmptyState } from '../utils/Ui';

const PREF_NAME: string = 'practice';

@Component
export struct ExamRecord {
  @State sessions: PracticeSession[] = [];
  @State kw: string = '';
  // 数据源刷新靠 IDataSource 的 onDataReloaded 通知，无需 @State（@State 代理会破坏私有字段）
  ds: LazyDataSource<PracticeSession> = new LazyDataSource<PracticeSession>([]);

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d: AppData) => {
      preferences.getPreferences(ctx, PREF_NAME).then((p: preferences.Preferences) => {
        const sIds: string = p.getSync('sess_ids', '') as string;
        const list: PracticeSession[] = [];
        if (sIds) {
          const arr: string[] = sIds.split(',');
          for (let i: number = 0; i < arr.length; i++) {
            const raw: string = p.getSync('sess_' + arr[i], '{}') as string;
            try {
              const rec: PracticeSession = JSON.parse(raw) as PracticeSession;
              list.push(rec);
            } catch (e) {
              // 忽略损坏记录
            }
          }
        }
        this.sessions = list;
        this.refresh();
      });
    });
  }

  // 同步过滤结果到 LazyForEach 数据源
  private refresh(): void {
    this.ds.setData(this.filterSessions());
  }

  // 按套题标题过滤
  private filterSessions(): PracticeSession[] {
    const k: string = this.kw.trim().toLowerCase();
    if (!k) {
      return this.sessions;
    }
    const out: PracticeSession[] = [];
    for (let i: number = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].setTitle.toLowerCase().includes(k)) {
        out.push(this.sessions[i]);
      }
    }
    return out;
  }

  private fmt(sec: number): string {
    const m: number = Math.floor(sec / 60);
    const s: number = sec % 60;
    return `${m}:${s < 10 ? '0' + s : '' + s}`;
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      BackHeader({ title: '我的真题演练记录' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索套题名称', text: this.kw })
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

      if (this.sessions.length === 0) {
        EmptyState({ emoji: '🎯', text: '还没有演练记录，去真题模考试试' })
      } else if (this.filterSessions().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw}」的套题` })
      } else {
        List() {
          LazyForEach(this.ds, (s: PracticeSession, i: number) => {
            ListItem() {
              Row() {
                IconTile({ emoji: '🎯', bg: $r('app.color.brand_light'), fg: $r('app.color.info'), dim: 40 })
                  .margin({ right: 12 })
                Column() {
                  Text(s.setTitle)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text(`${s.date} · 用时 ${this.fmt(s.durationSec)} · 掌握${s.master}/模糊${s.vague}/不会${s.fail}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 3 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(RADIUS.sm)
              .margin({ bottom: 6 })
              .shadow({ radius: 8, color: $r('app.color.card_stroke'), offsetY: 2 })
              .alignItems(VerticalAlign.Center)
            }
          }, (s: PracticeSession, i: number) => s.setTitle + '_' + i)
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

// 预览专用：mock 演练记录，Previewer 无需 prefs
@Preview
@Component
struct ExamRecordPreview {
  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
        Text('真题演练记录')
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
            Text('综合分析专项')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('2026-07-20 · 3 题')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('已评')
            .fontSize(12)
            .fontColor($r('app.color.brand'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.brand_light'))
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

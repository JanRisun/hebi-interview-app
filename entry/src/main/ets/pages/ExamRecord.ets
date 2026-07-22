// 我的真题演练记录：从本地 prefs 读取每套模考结果，支持搜索
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, PracticeSession } from '../model/Types';
import { BackHeader } from '../utils/BackHeader';
import { RADIUS } from '../utils/Theme';
import { IconTile, EmptyState } from '../utils/Ui';

const PREF_NAME: string = 'practice';

@Entry
@Component
struct ExamRecord {
  @State sessions: PracticeSession[] = [];
  @State kw: string = '';

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
      });
    });
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

  build() {
    Column() {
      BackHeader({ title: '我的真题演练记录' })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索套题名称', text: this.kw })
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

      if (this.sessions.length === 0) {
        EmptyState({ emoji: '🎯', text: '还没有演练记录，去真题模考试试' })
      } else if (this.filterSessions().length === 0) {
        EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw}」的套题` })
      } else {
        List() {
          ForEach(this.filterSessions(), (s: PracticeSession, i: number) => {
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
  }
}

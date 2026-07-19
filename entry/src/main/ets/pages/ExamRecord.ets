// 我的真题演练记录：从本地 prefs 读取每套模考结果，支持搜索
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, PracticeSession } from '../model/Types';
import { BackHeader } from '../utils/BackHeader';

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
          for (let i = 0; i < arr.length; i++) {
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
    for (let i = 0; i < this.sessions.length; i++) {
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
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .padding({ left: 14 })
      }
      .width('92%')
      .margin({ bottom: 10 })

      if (this.sessions.length === 0) {
        Text('还没有演练记录，去真题模考试试')
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else if (this.filterSessions().length === 0) {
        Text(`没有匹配「${this.kw}」的套题`)
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      } else {
        List() {
          ForEach(this.filterSessions(), (s: PracticeSession, i: number) => {
            ListItem() {
              Column() {
                Text(s.setTitle)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1f2d3d')
                Text(`${s.date} · 用时 ${this.fmt(s.durationSec)} · 掌握${s.master}/模糊${s.vague}/不会${s.fail}`)
                  .fontSize(12)
                  .fontColor('#888')
                  .margin({ top: 3 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .margin({ bottom: 6 })
              .alignItems(HorizontalAlign.Start)
            }
          }, (s: PracticeSession, i: number): string => s.setTitle + '_' + i)
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

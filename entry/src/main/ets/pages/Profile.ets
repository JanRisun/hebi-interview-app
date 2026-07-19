// 个人中心 Tab：我的收藏 / 我的学习记录 / 我的真题演练记录
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, Question, RatedItem, PracticeSession } from '../model/Types';

const PREF_NAME: string = 'practice';

@Component
export struct ProfileView {
  @State data: AppData | null = null;
  @State rated: RatedItem[] = [];        // 我的学习记录（自评索引）
  @State sessions: PracticeSession[] = []; // 我的真题演练记录

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d: AppData) => {
      this.data = d;
      this.loadRecords(ctx);
    });
  }

  // 从本地 prefs 读取学习记录与演练记录
  private loadRecords(ctx: common.UIAbilityContext): void {
    preferences.getPreferences(ctx, PREF_NAME).then((p: preferences.Preferences) => {
      // 我的学习记录（r_ids → 逐题评级）
      const rIds: string = p.getSync('r_ids', '') as string;
      const ratedList: RatedItem[] = [];
      if (rIds) {
        const arr: string[] = rIds.split(',');
        for (let i = 0; i < arr.length; i++) {
          const id: string = arr[i];
          const rating: string = p.getSync('r_' + id, '') as string;
          const q: Question | undefined = DataStore.questionById(id);
          const title: string = q ? q.title : id;
          ratedList.push({ id: id, title: title, rating: rating });
        }
      }
      this.rated = ratedList;

      // 我的真题演练记录（sess_ids → 每套结果）
      const sIds: string = p.getSync('sess_ids', '') as string;
      const sessList: PracticeSession[] = [];
      if (sIds) {
        const arr: string[] = sIds.split(',');
        for (let i = 0; i < arr.length; i++) {
          const raw: string = p.getSync('sess_' + arr[i], '{}') as string;
          try {
            const rec: PracticeSession = JSON.parse(raw) as PracticeSession;
            sessList.push(rec);
          } catch (e) {
            // 忽略损坏记录
          }
        }
      }
      this.sessions = sessList;
    });
  }

  private onFavorites(): void {
    router.pushUrl({ url: 'pages/Favorites' });
  }

  private onStudyRecord(): void {
    router.pushUrl({ url: 'pages/StudyRecord' });
  }

  private onExamRecord(): void {
    router.pushUrl({ url: 'pages/ExamRecord' });
  }

  // 通用入口行（标题 + 副标题 + 箭头）
  @Builder entryRow(icon: string, title: string, sub: string, cb: () => void) {
    Row() {
      Column() {
        Text(`${icon} ${title}`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1f2d3d')
        Text(sub)
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
    .margin({ bottom: 14 })
    .onClick(cb)
  }

  build() {
    Column() {
      Text('个人中心')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14385c')
        .margin({ top: 16, bottom: 12 })

      Scroll() {
        Column() {
          // 我的收藏（可点击进入收藏页，页内带搜索与返回）
          this.entryRow('⭐', '我的收藏', '已收藏的题目与知识点', () => this.onFavorites())

          // 我的学习记录（入口，点击进入带搜索的子页）
          this.entryRow('📖', '我的学习记录', `已自评 ${this.rated.length} 道`, () => this.onStudyRecord())

          // 我的真题演练记录（入口，点击进入带搜索的子页）
          this.entryRow('🎯', '我的真题演练记录', `已完成 ${this.sessions.length} 套`, () => this.onExamRecord())
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

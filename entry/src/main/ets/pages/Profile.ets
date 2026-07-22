// 个人中心 Tab：我的收藏 / 我的学习记录 / 我的真题演练记录
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, Question, RatedItem, PracticeSession } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { PageHero, IconTile, StatCard } from '../utils/Ui';

const PREF_NAME: string = 'practice';

@Component
export struct ProfileView {
  @State data: AppData | null = null;
  @State rated: RatedItem[] = [];        // 我的学习记录（自评索引）
  @State sessions: PracticeSession[] = []; // 我的真题演练记录
  @Consume pageStack: NavPathStack;

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
    this.pageStack.pushPathByName('Favorites', {} as Record<string, Object>);
  }

  private onStudyRecord(): void {
    this.pageStack.pushPathByName('StudyRecord', {} as Record<string, Object>);
  }

  private onExamRecord(): void {
    this.pageStack.pushPathByName('ExamRecord', {} as Record<string, Object>);
  }

  private onStudyPlan(): void {
    this.pageStack.pushPathByName('StudyPlan', {} as Record<string, Object>);
  }

  // 通用入口行：图标块 + 标题 + 副标题 + 箭头
  @Builder entryRow(emoji: string, bg: Resource, fg: Resource, title: string, sub: string, cb: () => void) {
    Row() {
      IconTile({ emoji: emoji, bg: bg, fg: fg, dim: 42 })
        .margin({ right: SPACE.md })
      Column() {
        Text(title)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(sub)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(FONT.title)
        .fontColor($r('app.color.text_arrow'))
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .margin({ bottom: SPACE.sm })
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
    .onClick(cb)
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 品牌头部
      PageHero({ emoji: '👤', title: '个人中心', subtitle: '你的学习档案与记录' })

      Scroll() {
        Column() {
          // 学习概览：数据卡
          if (this.data) {
            Row() {
              StatCard({ label: '已自评', value: `${this.rated.length}`, unit: '道' })
                .layoutWeight(1)
                .margin({ right: SPACE.sm })
              StatCard({ label: '已演练', value: `${this.sessions.length}`, unit: '套', accent: $r('app.color.accent') })
                .layoutWeight(1)
                .margin({ left: SPACE.sm })
            }
            .width('100%')
            .margin({ top: SPACE.md, bottom: SPACE.sm })
          }

          // 入口卡片
          this.entryRow('🩷', $r('app.color.accent_soft'), $r('app.color.accent'), '我的收藏', '已收藏的题目与知识点', () => this.onFavorites())
          this.entryRow('📝', $r('app.color.brand_light'), $r('app.color.brand'), '我的学习记录', `已自评 ${this.rated.length} 道`, () => this.onStudyRecord())
          this.entryRow('🎯', $r('app.color.brand_light'), $r('app.color.info'), '我的真题演练记录', `已完成 ${this.sessions.length} 套`, () => this.onExamRecord())
          this.entryRow('📅', $r('app.color.brand_light'), $r('app.color.brand'), '备考计划', '考试倒计时 + 复习任务清单', () => this.onStudyPlan())
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

// 预览专用：mock 个人中心，Previewer 无需 prefs/DataStore
@Preview
@Component
struct ProfilePreview {
  build() {
    Column() {
      Column() {
        Text('🧑')
          .fontSize(40)
        Text('面试备考人')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 8 })
        Text('鹤壁市 · 综合岗位')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .width('100%')
      .padding(SPACE.lg)
      .alignItems(HorizontalAlign.Center)

      Row() {
        Column() {
          Text('12')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text('收藏')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        Column() {
          Text('34')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text('已学题')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        Column() {
          Text('4')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text('模考套')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
      }
      .width('90%')
      .padding(SPACE.lg)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.md)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding({ top: 16 })
  }
}

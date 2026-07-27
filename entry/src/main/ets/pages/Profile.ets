// 个人中心 Tab：我的收藏 / 我的学习记录 / 我的真题演练记录
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DataStore } from '../model/DataStore';
import { AppData, Question, RatedItem, PracticeSession } from '../model/Types';
import { UserTagStore } from '../utils/UserTagStore';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { IconTile, StatCard, SectionTitle } from '../utils/Ui';

const PREF_NAME: string = 'practice';
// 按压态背景色：在受限作用域外预计算为模块级常量，供 entryRow 的 stateStyles 直接引用（避免 stateStyles 内 $r 不可见 / this 触发编译器断言）
const PRESSED_BG: Resource = $r('app.color.tag_bg');

@Component
export struct ProfileView {
  @State data: AppData | null = null;
  @State rated: RatedItem[] = [];        // 我的学习记录（自评索引）
  @State sessions: PracticeSession[] = []; // 我的真题演练记录
  @State markCount: number = 0;          // 我的标记（被标记的内容）数量
  @Consume pageStack: NavPathStack;

  // 订阅全局收藏/标签版本号：详情页加收藏/标签后自动重读，无需重启 app
  @StorageLink('favTagVersion') @Watch('onDataChange') tagVersion: number = 0;

  aboutToAppear(): void {
    this.refreshData();
  }

  // 收藏/标签变更时触发（@Watch）：重读最新数据（含我的标记）
  private onDataChange(): void {
    this.refreshData();
  }

  private refreshData(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d: AppData) => {
      this.data = d;
      this.loadRecords(ctx);
    });
    UserTagStore.markCount().then((c: number) => { this.markCount = c; });
  }

  private onKnowledge(): void {
    this.pageStack.pushPathByName('Knowledge', {} as Record<string, Object>);
  }
  private onQuestionBank(): void {
    this.pageStack.pushPathByName('QuestionBank', {} as Record<string, Object>);
  }
  private onMyTags(): void {
    this.pageStack.pushPathByName('MyMark', {} as Record<string, Object>);
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

  private onTestLab(): void {
    this.pageStack.pushPathByName('TestLab', {} as Record<string, Object>);
  }

  private onSettings(): void {
    this.pageStack.pushPathByName('Settings', {} as Record<string, Object>);
  }

  // 个人信息 Hero：渐变底 + 头像 + 昵称 + 地区，作为个人中心顶部品牌区
  @Builder profileHero() {
    Row() {
      IconTile({ emoji: '🧑', bg: $r('app.color.on_primary'), fg: $r('app.color.brand'), dim: 64 })
        .margin({ right: SPACE.md })
      Column() {
        Text('面试备考人')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_primary'))
        Text('鹤壁市 · 综合岗位')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.on_primary'))
          .opacity(0.85)
          .margin({ top: SPACE.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.brand'))
    .linearGradient({ angle: 135, colors: [[$r('app.color.brand'), 0], [$r('app.color.brand_dark'), 1]] })
    .borderRadius(RADIUS.lg)
    .margin({ top: SPACE.md, bottom: SPACE.md })
    .shadow({ radius: 14, color: $r('app.color.card_stroke'), offsetY: 4 })
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
    .stateStyles({
      pressed: {
        backgroundColor: PRESSED_BG
      }
    })
    .onClick(cb)
  }

  // 素材汇总小卡：数值 + 标签，点击跳转对应页面（知识点 / 真题库 / 我的标记）
  @Builder statLink(value: string, label: string, cb: () => void) {
    Column() {
      Text(value)
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand'))
      Text(label)
        .fontSize(FONT.mini)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: SPACE.md, bottom: SPACE.md })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
    .onClick(cb)
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  // 订阅字号变化，触发本常驻 Tab 重渲染（FONT getter 实时读取 AppStorage('fontScale')）
  @StorageProp('fontScale') _fs: number = 1;

  build() {
    Column() {
      Scroll() {
        Column() {
          // 顶部品牌区：用户信息
          this.profileHero()

          // 学习概览
          if (this.data) {
            SectionTitle({ title: '学习概览', sub: '你的备考进度一览' })
            Row() {
              StatCard({ label: '已自评', value: `${this.rated.length}`, unit: '道' })
                .layoutWeight(1)
                .margin({ right: SPACE.sm })
              StatCard({ label: '已演练', value: `${this.sessions.length}`, unit: '套', accent: $r('app.color.accent') })
                .layoutWeight(1)
                .margin({ left: SPACE.sm })
            }
            .width('100%')
            .margin({ bottom: SPACE.sm })
          }

          // 内容库快捷统计（点击跳转）
          if (this.data) {
            SectionTitle({ title: '内容库' })
            Row({ space: SPACE.sm }) {
              this.statLink(`${this.data.articles.length}`, '知识点', () => this.onKnowledge())
              this.statLink(`${this.data.questions.length}`, '真题库', () => this.onQuestionBank())
              this.statLink(`${this.markCount}`, '我的标记', () => this.onMyTags())
            }
            .width('100%')
            .margin({ bottom: SPACE.sm })
          }

          // 我的
          SectionTitle({ title: '我的' })
          this.entryRow('🩷', $r('app.color.accent_soft'), $r('app.color.accent'), '我的收藏', '已收藏的题目与知识点', () => this.onFavorites())
          this.entryRow('📝', $r('app.color.brand_light'), $r('app.color.brand'), '我的学习记录', `已自评 ${this.rated.length} 道`, () => this.onStudyRecord())
          this.entryRow('🎯', $r('app.color.brand_light'), $r('app.color.info'), '我的真题演练记录', `已完成 ${this.sessions.length} 套`, () => this.onExamRecord())

          // 工具与设置
          SectionTitle({ title: '工具与设置' })
          this.entryRow('📅', $r('app.color.brand_light'), $r('app.color.brand'), '备考计划', '考试倒计时 + 复习任务清单', () => this.onStudyPlan())
          this.entryRow('🧪', $r('app.color.brand_light'), $r('app.color.brand'), '测试功能', '实验性能力调试与演示入口', () => this.onTestLab())
          this.entryRow('⚙️', $r('app.color.brand_light'), $r('app.color.brand'), '设置',
            '外观 · 文字大小 · 备考提醒', () => this.onSettings())
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .padding({ top: this.safeTop, bottom: this.safeBottom })
      // 官方系统 Tab 栏已位于内容区下方，底部仅留系统安全区，
      // 避免最后一张入口卡片被悬浮 Tab 栏遮挡
  }
}

// 预览专用：mock 个人中心，Previewer 无需 prefs/DataStore
@Preview
@Component
struct ProfilePreview {
  @Builder previewStat(v: string, l: string) {
    Column() {
      Text(v)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand'))
      Text(l)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: SPACE.md, bottom: SPACE.md })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
  }

  build() {
    Column() {
      // 渐变 Hero
      Row() {
        Column() {
          Text('🧑')
            .fontSize(30)
        }
        .width(64)
        .height(64)
        .borderRadius(20)
        .backgroundColor($r('app.color.on_primary'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ right: SPACE.md })
        Column() {
          Text('面试备考人')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_primary'))
          Text('鹤壁市 · 综合岗位')
            .fontSize(13)
            .fontColor($r('app.color.on_primary'))
            .opacity(0.85)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('92%')
      .padding(SPACE.lg)
      .backgroundColor($r('app.color.brand'))
      .linearGradient({ angle: 135, colors: [[$r('app.color.brand'), 0], [$r('app.color.brand_dark'), 1]] })
      .borderRadius(RADIUS.lg)
      .margin({ top: 16, bottom: SPACE.sm })

      // 学习概览
      Row() {
        Column() {
          Text('12')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text('已自评')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(SPACE.lg)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.lg)
        .alignItems(HorizontalAlign.Start)
        Column() {
          Text('4')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent'))
          Text('已演练')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(SPACE.lg)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.lg)
        .margin({ left: SPACE.sm })
        .alignItems(HorizontalAlign.Start)
      }
      .width('92%')
      .margin({ bottom: SPACE.sm })

      // 内容库
      Row({ space: SPACE.sm }) {
        this.previewStat('120', '知识点')
        this.previewStat('320', '真题库')
        this.previewStat('8', '我的标记')
      }
      .width('92%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding({ top: 16 })
  }
}

// 备考计划：考试倒计时 + 面试复习任务清单 + 每日提醒 + 今日备考
// 数据存本地 preferences（PREF_NAME='practice'）
// 每日提醒用系统代理提醒（reminderAgentManager），App 关了也照常弹通知
import { common, bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { router } from '@kit.ArkUI';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackHeader } from '../utils/BackHeader';
import { FONT, RADIUS, SPACE } from '../utils/Theme';
import { DataStore } from '../model/DataStore';
import { Article, MockSet, AppData } from '../model/Types';

const PREF_NAME: string = 'practice';
const KEY_EXAM_DATE: string = 'plan_exam_date';
const KEY_TASKS: string = 'plan_tasks';
const KEY_REMIND_ON: string = 'plan_remind_on';
const KEY_REMIND_HOUR: string = 'plan_remind_hour';
const KEY_REMIND_MIN: string = 'plan_remind_min';
const KEY_REMIND_ID: string = 'plan_remind_id';
const REMIND_NOTIFY_ID: number = 1001;   // 固定通知 ID，重复发布自动覆盖

// 内置面试题型模块（默认复习清单，用户可增删），通用备考口径，不绑定具体岗位
const DEFAULT_MODULES: string[] = [
  '综合分析能力',
  '组织管理能力',
  '人际沟通能力',
  '情景模拟应对',
  '时政热点积累',
  '自我认知梳理'
];

// 日期选择器回调值（与系统 DatePickerResult 字段一致）
interface PickerDateRes {
  year: number;
  month: number;   // 0-based
  day: number;
}

// 时间选择器回调值（与系统 TimePickerResult 字段一致）
interface PickerTimeRes {
  hour: number;
  minute: number;
}

// 今日备考内容（按日期 seed 轮换）
interface TodayPlan {
  mat: Article;
  know: Article;
  set: MockSet;
}

interface StudyTask {
  id: string;
  title: string;
  done: boolean;
}

@Entry
@Component
struct StudyPlan {
  @State examDateStr: string = '';     // 'YYYY-MM-DD'，空=未设置
  @State daysLeft: number = -1;        // 距今天数；-1 表示未设置
  @State tasks: StudyTask[] = [];
  @State newTask: string = '';          // 输入框临时值
  @State remindOn: boolean = false;     // 每日提醒开关
  @State remindHour: number = 20;       // 提醒小时
  @State remindMinute: number = 0;       // 提醒分钟
  @State remindId: number = -1;        // 已发布的代理提醒 ID（取消用）
  @State today: TodayPlan | null = null;  // 今日备考内容
  private prefs: preferences.Preferences | null = null;

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(ctx, PREF_NAME).then((p: preferences.Preferences): void => {
      this.prefs = p;
      this.examDateStr = p.getSync(KEY_EXAM_DATE, '') as string;
      this.recalcDays();
      const raw: string = p.getSync(KEY_TASKS, '') as string;
      if (raw) {
        try {
          const arr: StudyTask[] = JSON.parse(raw) as StudyTask[];
          this.tasks = arr;
        } catch (e) {
          this.tasks = this.buildDefaults();
          this.saveTasks();
        }
      } else {
        this.tasks = this.buildDefaults();
        this.saveTasks();
      }
      // 读取每日提醒配置
      this.remindOn = p.getSync(KEY_REMIND_ON, false) as boolean;
      this.remindHour = p.getSync(KEY_REMIND_HOUR, 20) as number;
      this.remindMinute = p.getSync(KEY_REMIND_MIN, 0) as number;
      this.remindId = p.getSync(KEY_REMIND_ID, -1) as number;
    });
    // 今日备考内容（需 DataStore 先加载）
    DataStore.load(ctx).then((): void => {
      this.today = this.pickToday();
    });
  }

  // 用内置模块生成默认任务清单
  private buildDefaults(): StudyTask[] {
    const list: StudyTask[] = [];
    for (let i: number = 0; i < DEFAULT_MODULES.length; i++) {
      list.push({ id: 'm_' + i.toString(), title: DEFAULT_MODULES[i], done: false });
    }
    return list;
  }

  // 重新计算距今天数（考试日 - 今天，按天取整）
  private recalcDays(): void {
    if (!this.examDateStr) {
      this.daysLeft = -1;
      return;
    }
    const today: Date = new Date();
    today.setHours(0, 0, 0, 0);
    const parts: string[] = this.examDateStr.split('-');
    const y: number = Number(parts[0]);
    const m: number = Number(parts[1]) - 1;
    const d: number = Number(parts[2]);
    const exam: Date = new Date(y, m, d);
    const diff: number = Math.floor((exam.getTime() - today.getTime()) / 86400000);
    this.daysLeft = diff;
  }

  private saveExamDate(): void {
    if (this.prefs) {
      this.prefs.putSync(KEY_EXAM_DATE, this.examDateStr);
      this.prefs.flush();
    }
  }

  private saveTasks(): void {
    if (this.prefs) {
      this.prefs.putSync(KEY_TASKS, JSON.stringify(this.tasks));
      this.prefs.flush();
    }
  }

  private saveRemind(): void {
    if (!this.prefs) {
      return;
    }
    this.prefs.putSync(KEY_REMIND_ON, this.remindOn);
    this.prefs.putSync(KEY_REMIND_HOUR, this.remindHour);
    this.prefs.putSync(KEY_REMIND_MIN, this.remindMinute);
    this.prefs.putSync(KEY_REMIND_ID, this.remindId);
    this.prefs.flush();
  }

  // 按日期轮换取今日素材 / 知识 / 套题
  private pickToday(): TodayPlan | null {
    const data: AppData | null = DataStore.data;
    if (!data || data.articles.length === 0 || data.sets.length === 0) {
      return null;
    }
    const now: Date = new Date();
    const offset: number = now.getMonth() * 31 + now.getDate();
    const all: Article[] = data.articles;
    const mats: Article[] = all.filter((a: Article): boolean => a.category.indexOf('素材') >= 0);
    const knows: Article[] = all.filter((a: Article): boolean => a.category.indexOf('知识') >= 0);
    const matPool: Article[] = mats.length > 0 ? mats : all;
    const knowPool: Article[] = knows.length > 0 ? knows : all;
    const sets: MockSet[] = DataStore.sets();
    const mat: Article = matPool[offset % matPool.length];
    const know: Article = knowPool[offset % knowPool.length];
    const set: MockSet = sets[offset % sets.length];
    return { mat: mat, know: know, set: set };
  }

  // 弹出日期选择器（API 18+ 推荐 getUIContext().showDatePickerDialog）
  private onPickDate(): void {
    const today: Date = new Date();
    const max: Date = new Date();
    max.setFullYear(max.getFullYear() + 2);
    let sel: Date = today;
    if (this.examDateStr) {
      const parts: string[] = this.examDateStr.split('-');
      sel = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }
    const uiCtx = this.getUIContext();
    uiCtx?.showDatePickerDialog({
      start: today,
      end: max,
      selected: sel,
      onAccept: (value: PickerDateRes): void => {
        const y: number = value.year;
        const m: number = value.month + 1;  // month 为 0-based
        const d: number = value.day;
        const mm: string = m < 10 ? '0' + m.toString() : m.toString();
        const dd: string = d < 10 ? '0' + d.toString() : d.toString();
        this.examDateStr = y.toString() + '-' + mm + '-' + dd;
        this.recalcDays();
        this.saveExamDate();
      }
    });
  }

  // 弹出时间选择器（设置每日提醒时刻）
  private onPickTime(): void {
    const sel: Date = new Date();
    sel.setHours(this.remindHour, this.remindMinute, 0, 0);
    const uiCtx = this.getUIContext();
    uiCtx?.showTimePickerDialog({
      selected: sel,
      onAccept: (value: PickerTimeRes): void => {
        this.remindHour = value.hour;
        this.remindMinute = value.minute;
        this.saveRemind();
        // 已开启则重新发布（固定通知 ID 自动覆盖旧的）
        if (this.remindOn) {
          this.doPublish();
        }
      }
    });
  }

  // 开关：开 → 请求通知授权后发布；关 → 取消
  private onToggleRemind(on: boolean): void {
    this.remindOn = on;
    this.saveRemind();
    if (on) {
      this.requestAndPublish();
    } else {
      this.cancelRemind();
    }
  }

  // 请求通知授权后发布代理提醒
  private requestAndPublish(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    notificationManager.requestEnableNotification(ctx).then((): void => {
      this.doPublish();
    }).catch((): void => {
      // 已授权或用户拒绝，仍尝试发布（拒绝时系统会拦截）
      this.doPublish();
    });
  }

  // 发布每日代理提醒（ReminderRequestAlarm，每天重复）
  private doPublish(): void {
    const pkg: string = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).appInfo.name;
    const req: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: this.remindHour,
      minute: this.remindMinute,
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      actionButton: [
        { title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }
      ],
      wantAgent: {
        pkgName: pkg,
        abilityName: 'EntryAbility'
      },
      title: '面试备考提醒',
      content: '今日素材 + 知识 + 1 套套题已就绪，点击开始',
      notificationId: REMIND_NOTIFY_ID,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      ringDuration: 5
    };
    reminderAgentManager.publishReminder(req).then((id: number): void => {
      this.remindId = id;
      this.saveRemind();
    }).catch((err: BusinessError): void => {
      hilog.error(0x1000, 'StudyPlan', '发布提醒失败 code=%{public}d msg=%{public}s', err.code, err.message);
    });
  }

  // 取消已发布的代理提醒
  private cancelRemind(): void {
    if (this.remindId < 0) {
      return;
    }
    const id: number = this.remindId;
    reminderAgentManager.cancelReminder(id).then((): void => {
      this.remindId = -1;
      this.saveRemind();
    }).catch((err: BusinessError): void => {
      hilog.error(0x1000, 'StudyPlan', '取消提醒失败 %{public}s', JSON.stringify(err));
    });
  }

  // 切换任务完成态（重新赋值数组以触发 UI 刷新）
  private toggleTask(id: string): void {
    const next: StudyTask[] = [];
    for (let i: number = 0; i < this.tasks.length; i++) {
      const t: StudyTask = this.tasks[i];
      if (t.id === id) {
        next.push({ id: t.id, title: t.title, done: !t.done });
      } else {
        next.push(t);
      }
    }
    this.tasks = next;
    this.saveTasks();
  }

  // 删除任务
  private delTask(id: string): void {
    const out: StudyTask[] = [];
    for (let i: number = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id !== id) {
        out.push(this.tasks[i]);
      }
    }
    this.tasks = out;
    this.saveTasks();
  }

  // 添加自定义任务（重新赋值数组以触发刷新）
  private addTask(): void {
    const t: string = this.newTask.trim();
    if (!t) {
      return;
    }
    const list: StudyTask[] = [];
    for (let i: number = 0; i < this.tasks.length; i++) {
      list.push(this.tasks[i]);
    }
    list.push({ id: 't_' + Date.now().toString(), title: t, done: false });
    this.tasks = list;
    this.newTask = '';
    this.saveTasks();
  }

  // 已完成数量
  private doneCount(): number {
    let c: number = 0;
    for (let i: number = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].done) {
        c++;
      }
    }
    return c;
  }

  // 补零：1 位时分补 0
  private fmt2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  build() {
    Column() {
      BackHeader({ title: '备考计划' })

      Scroll() {
        Column() {
          // 倒计时卡片（点击设置/切换考试日）
          this.buildCountdown()
          // 每日提醒开关 + 时间
          this.buildRemind()
          // 今日备考内容
          this.buildToday()
          // 复习任务清单
          this.buildTaskList()
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
  }

  // 倒计时卡片
  @Builder buildCountdown() {
    Column() {
      if (this.daysLeft < 0) {
        Text('未设置考试日期')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('点击设置目标考试日，开启倒计时')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
      } else if (this.daysLeft === 0) {
        Text('就是今天！')
          .fontSize(FONT.display)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('稳住，你准备好了')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
      } else if (this.daysLeft > 0) {
        Row() {
          Text(`${this.daysLeft}`)
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
          Text('天')
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: SPACE.xs, top: SPACE.sm })
        }
        Text(`距离考试（${this.examDateStr}）`)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.sm })
      } else {
        Text('考试已结束')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))
        Text(`考试日 ${this.examDateStr}`)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
      }

      if (this.examDateStr) {
        Text('点击卡片可切换考试日期')
          .fontSize(FONT.mini)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: SPACE.md })
      }
    }
    .width('100%')
    .padding(SPACE.xl)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .alignItems(HorizontalAlign.Center)
    .margin({ bottom: SPACE.lg })
    .onClick(() => this.onPickDate())
  }

  // 每日提醒卡片
  @Builder buildRemind() {
    Column() {
      Row() {
        Column() {
          Text('每日备考提醒')
            .fontSize(FONT.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.remindOn
            ? `每天 ${this.fmt2(this.remindHour)}:${this.fmt2(this.remindMinute)} 推送`
            : '开启后每天定时推送今日素材/知识/套题')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: SPACE.xs })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.remindOn) {
          Text(`${this.fmt2(this.remindHour)}:${this.fmt2(this.remindMinute)}`)
            .fontSize(FONT.body)
            .fontColor($r('app.color.brand'))
            .margin({ right: SPACE.sm })
            .onClick(() => this.onPickTime())
        } else {
          Text('设置时间')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.brand'))
            .margin({ right: SPACE.sm })
            .onClick(() => this.onPickTime())
        }

        Toggle({ type: ToggleType.Switch, isOn: this.remindOn })
          .onChange((isOn: boolean): void => {
            this.onToggleRemind(isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .margin({ bottom: SPACE.lg })
  }

  // 今日备考内容
  @Builder buildToday() {
    Column() {
      Text('今日备考')
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_title'))
        .width('100%')
        .margin({ bottom: SPACE.sm })

      if (this.today) {
        this.todayCard('今日素材', this.today.mat.title, this.today.mat.summary)
        this.todayCard('今日知识', this.today.know.title, this.today.know.summary)
        // 今日套题
        Column() {
          Text('今日套题演练')
            .fontSize(FONT.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.today.set.title)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: SPACE.xs })
          Button('开始演练')
            .width('100%')
            .height(40)
            .fontSize(FONT.bodySm)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .margin({ top: SPACE.sm })
            .onClick(() => {
              router.pushUrl({ url: 'pages/Practice', params: { setId: this.today.set?.id ?? 0 } });
            })
        }
        .width('100%')
        .padding(SPACE.md)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.sm)
        .margin({ bottom: SPACE.sm })
      } else {
        Text('暂无可用素材/套题')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .margin({ bottom: SPACE.lg })
  }

  // 今日素材/知识卡片
  @Builder todayCard(tag: string, title: string, desc: string) {
    Column() {
      Text(tag)
        .fontSize(FONT.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(title)
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: SPACE.xs })
      Text(desc)
        .fontSize(FONT.mini)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: SPACE.xs })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(SPACE.md)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.sm)
    .margin({ bottom: SPACE.sm })
  }

  // 复习任务清单
  @Builder buildTaskList() {
    Column() {
      Row() {
        Text('复习任务清单')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .layoutWeight(1)
        Text(`已完成 ${this.doneCount()}/${this.tasks.length}`)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: SPACE.sm })

      // 完成进度条
      if (this.tasks.length > 0) {
        Progress({ value: this.doneCount(), total: this.tasks.length, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .margin({ bottom: SPACE.md })
          .color($r('app.color.brand'))
      }

      // 任务列表
      ForEach(this.tasks, (t: StudyTask) => {
        Row() {
          Checkbox()
            .select(t.done)
            .onChange((isOn: boolean): void => {
              this.toggleTask(t.id);
            })
            .margin({ right: SPACE.sm })
          Text(t.title)
            .fontSize(FONT.body)
            .fontColor(t.done ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
            .decoration({ type: t.done ? TextDecorationType.LineThrough : TextDecorationType.None })
            .layoutWeight(1)
          Text('删除')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.danger'))
            .onClick(() => this.delTask(t.id))
        }
        .width('100%')
        .padding(SPACE.md)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(RADIUS.sm)
        .margin({ bottom: SPACE.xs })
      }, (t: StudyTask) => t.id)

      // 添加自定义任务
      Row() {
        TextInput({ placeholder: '添加自定义复习任务', text: this.newTask })
          .onChange((v: string): void => {
            this.newTask = v;
          })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: 14 })
        Button('添加')
          .height(40)
          .fontSize(FONT.bodySm)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .borderRadius(RADIUS.pill)
          .margin({ left: SPACE.sm })
          .onClick(() => this.addTask())
      }
      .width('100%')
      .margin({ top: SPACE.sm })
    }
    .width('100%')
  }
}

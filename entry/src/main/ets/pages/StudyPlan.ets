// 备考计划：考试倒计时 + 面试复习任务清单
// 数据存本地 preferences（PREF_NAME='practice'），key：plan_exam_date / plan_tasks
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BackHeader } from '../utils/BackHeader';
import { FONT, RADIUS, SPACE } from '../utils/Theme';

// 日期选择器回调值（与系统 DatePickerResult 字段一致）
interface PickerDateRes {
  year: number;
  month: number;   // 0-based
  day: number;
}

const PREF_NAME: string = 'practice';
const KEY_EXAM_DATE: string = 'plan_exam_date';
const KEY_TASKS: string = 'plan_tasks';

// 内置面试题型模块（默认复习清单，用户可增删），通用备考口径，不绑定具体岗位
const DEFAULT_MODULES: string[] = [
  '综合分析能力',
  '组织管理能力',
  '人际沟通能力',
  '情景模拟应对',
  '时政热点积累',
  '自我认知梳理'
];

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
        // 首次进入：用内置模块初始化清单
        this.tasks = this.buildDefaults();
        this.saveTasks();
      }
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

  build() {
    Column() {
      BackHeader({ title: '备考计划' })

      Scroll() {
        Column() {
          // 倒计时卡片（点击设置/切换考试日）
          this.buildCountdown()
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

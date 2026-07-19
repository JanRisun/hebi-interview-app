// 真题模考 Tab（档位 B）：选套 → 限时连做 → 交卷复盘 → 练习报告
// 对齐华图/粉笔逻辑：模考阶段锁答案，复盘才出【参考答案 · 逐字稿】，逐题自评（本地持久化）
// 顶部加搜索框搜真题；每完成一套写一条演练记录供「个人中心」读取
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Question, MockSet, PracticeSession } from '../model/Types';
import { preferences } from '@kit.ArkData';
import { RADIUS } from '../utils/Theme';
import { RecorderBar } from '../utils/RecorderBar';
import { fileIo } from '@kit.CoreFileKit';
import { vibrator } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const PREF_NAME: string = 'practice';

@Component
export struct PracticeView {
  @State data: AppData | null = null;
  @State sets: MockSet[] = [];
  @State phase: 'select' | 'exam' | 'review' | 'report' = 'select';
  @State curSet: MockSet | null = null;
  @State qList: Question[] = [];
  @State idx: number = 0;
  @State elapsed: number = 0;                 // 整卷总用时（秒，正计时，含超时）
  @State stage: 'think' | 'speak' = 'think'; // 当前分段：思考中 / 作答中
  @State remain: number = 30;                 // 当前分段剩余秒数（作答超时后变负，用于显示「超时 Xs」）
  @State timerStarted: boolean = false;       // 用户是否点击了「开始答题」（false=待机态，不倒计时）
  @State notes: Record<string, string> = {};   // 用户作答要点（按题目 id）
  @State ratings: Record<string, string> = {}; // 自评：掌握/模糊/不会（按题目 id）
  @State kw: string = '';                      // 顶部搜索框
  private pref: preferences.Preferences | null = null;
  private timer: number = 0;

  // 当前题 id（getter，便于笔记/自评绑定）
  get curId(): string {
    return this.qList[this.idx] ? this.qList[this.idx].id : '';
  }

  // 本套建议总时长（秒）：思考+作答；无数据则兜底 10 分钟
  get suggestedSec(): number {
    const s: MockSet | null = this.curSet;
    if (!s) return 600;
    const t: number = (s.totalThink || 0) + (s.totalSpeak || 0);
    return t > 0 ? t : 600;
  }

  // 当前题思考时长（秒）：套题有则用之，无则默认 30
  get thinkSec(): number {
    const s: MockSet | null = this.curSet;
    const v: number = (s && typeof s.totalThink === 'number' && s.totalThink > 0) ? s.totalThink : 30;
    return Number.isFinite(v) ? v : 30;
  }

  // 当前题作答时长（秒）：套题有则用之，无则默认 150（2分30秒）
  get speakSec(): number {
    const s: MockSet | null = this.curSet;
    const v: number = (s && typeof s.totalSpeak === 'number' && s.totalSpeak > 0) ? s.totalSpeak : 150;
    return Number.isFinite(v) ? v : 150;
  }

  // 统计各评级数量（供报告页 builder 引用，避免在 builder 内写 const）
  get masterCount(): number { return this.countRating('掌握'); }
  get vagueCount(): number { return this.countRating('模糊'); }
  get failCount(): number { return this.countRating('不会'); }

  // 顶部搜索过滤后的套题列表
  get filteredSets(): MockSet[] {
    const k: string = (this.kw || '').trim().toLowerCase();
    if (!k) return this.sets;
    return this.sets.filter((s: MockSet): boolean => {
      return s.title.toLowerCase().indexOf(k) >= 0 || s.source.toLowerCase().indexOf(k) >= 0;
    });
  }

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d: AppData) => {
      this.data = d;
      this.sets = DataStore.sets();
      preferences.getPreferences(ctx, PREF_NAME).then((p: preferences.Preferences) => {
        this.pref = p;
        // 读回历史自评，复用 Tier A 的 r_ 键
        const r: Record<string, string> = {};
        this.sets.forEach((set: MockSet): void => {
          set.questionIds.forEach((id: string): void => {
            const v: string = p.getSync('r_' + id, '') as string;
            if (v) r[id] = v;
            const n: string = p.getSync('n_' + id, '') as string;
            if (n) this.notes[id] = n;
          });
        });
        this.ratings = r;
        // 支持从首页/分类深链直接进入某套
        const params: Record<string, Object> | undefined = router.getParams() as Record<string, Object> | undefined;
        if (params && params['setId']) {
          const sid: string = params['setId'] as string;
          const target: MockSet | undefined = this.sets.find((x: MockSet): boolean => x.id === sid);
          if (target) this.startSet(target);
        }
      });
    });
  }

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timer !== 0) {
      clearInterval(this.timer);
      this.timer = 0;
    }
  }

  // 读该题的本地语音识别转写（RecorderBar 存的 rec_<id>.txt）
  private asrOf(id: string): string {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      return fileIo.readTextSync(ctx.filesDir + '/rec_' + id + '.txt');
    } catch (e) {
      return '';
    }
  }

  // 分段计时主循环：思考→作答倒计时 → 超时继续计（振动提示）
  // 重要：初始值全部用本地变量算好再赋 @State，避免 getter 时序/NaN 问题
  startTimer(): void {
    this.clearTimer();
    const s: MockSet | null = this.curSet;
    // 从 curSet 读时长，三层兜底确保永远不是 NaN/0/负数
    const tThink: number = (s && typeof s.totalThink === 'number' && s.totalThink > 0) ? s.totalThink : 30;
    const tSpeak: number = (s && typeof s.totalSpeak === 'number' && s.totalSpeak > 0) ? s.totalSpeak : 150;

    this.timerStarted = true;          // 标记：用户已开始答题，UI 从待机态切到倒计
    this.stage = 'think';
    this.remain = tThink;             // 用本地变量（已保证有效），不走 getter
    this.timer = setInterval((): void => {
      this.elapsed++;          // 整卷总用时累加（含超时）
      this.remain--;          // 当前分段倒计时
      if (this.remain <= 0) {
        if (this.stage === 'think') {
          // 思考结束 → 进入作答，重置分段计时并响提示音
          this.stage = 'speak';
          this.remain = tSpeak;       // 用闭包捕获的本地变量，不走 getter
          this.beep('start');
        } else if (this.remain === 0) {
          // 作答时间刚到 → 响提示音（不强制跳题，给用户缓冲；remain 继续变负显示超时）
          this.beep('timeout');
        }
      }
    }, 1000);
  }

  // 切到下一题时重置分段计时（整卷 elapsed 不清零，timerStarted 保持）
  private resetStage(): void {
    this.stage = 'think';
    const s: MockSet | null = this.curSet;
    this.remain = (s && typeof s.totalThink === 'number' && s.totalThink > 0) ? s.totalThink : 30;
  }

  // 时间节点提示：用振动（马达）提醒考生 —— 思考结束切作答、作答超时
  // 关键修复：
  //  1) usage 必须用 'alarm'（受系统「声音模式」管控：振动/响铃模式即振）；
  //     不能再用 'unknown'/'touch'（受「系统触感反馈」开关管控，该开关默认常关→不振动）。
  //  2) 必须在 module.json5 声明 ohos.permission.VIBRATE 权限，否则调用被系统拒绝（且原代码被 catch 吞掉不报）。
  //  3) 模拟器无物理马达，必须在真机验证。
  private beep(kind: 'start' | 'timeout'): void {
    try {
      const dur: number = kind === 'start' ? 300 : 700;
      vibrator.startVibration(
        { type: 'time', duration: dur },
        { id: 1, usage: 'alarm' }
      )
        .then(() => {
          hilog.info(0x1000, 'Practice', '计时振动成功 kind=%{public}s', kind);
        })
        .catch((err: unknown) => {
          hilog.error(0x1000, 'Practice', '计时振动失败 kind=%{public}s err=%{public}s', kind, JSON.stringify(err));
        });
    } catch (e) {
      hilog.error(0x1000, 'Practice', '计时振动异常 %{public}s', JSON.stringify(e));
    }
  }

  startSet(s: MockSet): void {
    const qs: Question[] = DataStore.questionsOfSet(s.id);
    if (qs.length === 0) return;
    this.curSet = s;
    this.qList = qs;
    this.idx = 0;
    this.elapsed = 0;
    this.timerStarted = false;          // 待机态：用户需手动点「开始答题」才启动倒计
    this.remain = (s && typeof s.totalThink === 'number' && s.totalThink > 0) ? s.totalThink : 30;
    this.phase = 'exam';
    // 不再自动 startTimer()——等用户点「开始答题」按钮
  }

  // 随机单题自测（保留 Tier A 能力）：合成一个虚拟套题
  startSingle(): void {
    const all: Question[] = (this.data ? this.data.questions : []);
    if (all.length === 0) return;
    const q: Question = all[Math.floor(Math.random() * all.length)];
    const fake: MockSet = {
      id: '__single__',
      title: '随机单题自测',
      source: q.source,
      questionIds: [q.id],
      totalThink: q.thinkTime || 30,
      totalSpeak: q.speakTime || 150
    };
    this.curSet = fake;
    this.qList = [q];
    this.idx = 0;
    this.elapsed = 0;
    this.timerStarted = false;          // 待机态
    this.remain = (fake && typeof fake.totalThink === 'number' && fake.totalThink > 0) ? fake.totalThink : 30;
    this.phase = 'exam';
    // 不再自动 startTimer()——等用户点「开始答题」按钮
  }

  next(): void {
    if (this.idx < this.qList.length - 1) {
      this.idx++;
      this.resetStage();   // 新题：重置为「思考中」倒计时
    } else {
      this.submit();
    }
  }

  submit(): void {
    this.clearTimer();
    this.timerStarted = false;
    this.phase = 'review';
  }

  backToSelect(): void {
    this.clearTimer();
    this.timerStarted = false;
    this.phase = 'select';
    this.curSet = null;
    this.qList = [];
    this.idx = 0;
    this.elapsed = 0;
  }

  // ArkTS strict: 避免对象 spread 和计算属性名 —— 用显式拷贝
  private updateRatings(id: string, r: string): void {
    const nextR: Record<string, string> = {};
    const keys: string[] = Object.keys(this.ratings);
    for (let k: number = 0; k < keys.length; k++) {
      nextR[keys[k]] = this.ratings[keys[k]];
    }
    nextR[id] = r;
    this.ratings = nextR;
    if (this.pref) {
      const p: preferences.Preferences = this.pref;
      p.putSync('r_' + id, r);
      // 维护自评索引（供个人中心「我的学习记录」读取）
      const ids: string = p.getSync('r_ids', '') as string;
      const arr: string[] = ids ? ids.split(',') : [];
      if (arr.indexOf(id) < 0) {
        arr.push(id);
        p.putSync('r_ids', arr.join(','));
      }
      p.flushSync();
    }
  }

  // 每完成一套模考，写一条演练记录（供个人中心读取）
  private saveSession(): void {
    const p: preferences.Preferences | null = this.pref;
    if (!p || !this.curSet) return;
    const ts: string = new Date().getTime().toString();
    const rec: PracticeSession = {
      setTitle: this.curSet.title,
      date: this.fmtDate(),
      durationSec: this.elapsed,
      master: this.masterCount,
      vague: this.vagueCount,
      fail: this.failCount
    };
    p.putSync('sess_' + ts, JSON.stringify(rec));
    const ids: string = p.getSync('sess_ids', '') as string;
    const arr: string[] = ids ? ids.split(',') : [];
    arr.push(ts);
    p.putSync('sess_ids', arr.join(','));
    p.flushSync();
  }

  // 同上：避免 notes 的 spread + 计算属性名
  private updateNotes(id: string, v: string): void {
    const nextN: Record<string, string> = {};
    const keys: string[] = Object.keys(this.notes);
    for (let k: number = 0; k < keys.length; k++) {
      nextN[keys[k]] = this.notes[keys[k]];
    }
    nextN[id] = v;
    this.notes = nextN;
    this.persistNote(id, v);
  }

  fmt(sec: number): string {
    if (!Number.isFinite(sec)) return '--:--';   // NaN / Infinity / undefined 全部显示为占位符
    const s_num: number = Math.floor(sec);
    const m: number = Math.floor(s_num / 60);
    const s: number = s_num % 60;
    return `${m}:${s < 10 ? '0' + s : '' + s}`;
  }

  private fmtDate(): string {
    const d: Date = new Date();
    const p2: (n: number) => string = (n: number): string => (n < 10 ? '0' + n : '' + n);
    return `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())} ${p2(d.getHours())}:${p2(d.getMinutes())}`;
  }

  persistNote(id: string, v: string): void {
    if (this.pref) {
      this.pref.putSync('n_' + id, v);
      this.pref.flushSync();
    }
  }

  // ── onClick 回调：ArkTS strict 禁止 lambda 内用 this → 提取为成员方法 ──

  private onStartSet(s: MockSet): void {
    this.startSet(s);
  }

  private onStartSingle(): void {
    this.startSingle();
  }

  private onBackToSelect(): void {
    this.backToSelect();
  }

  private onNext(): void {
    this.next();
  }

  private onSubmit(): void {
    this.submit();
  }

  private onToReport(): void {
    this.saveSession();
    this.phase = 'report';
  }

  private onRate(id: string, label: string): void {
    this.updateRatings(id, label);
  }

  private onNoteChange(v: string): void {
    this.updateNotes(this.curId, v);
  }

  // 自评选择行（复盘/报告复用）
  @Builder ratingRow(id: string) {
    Row({ space: 10 }) {
      this.rateBtn(id, '掌握', $r('app.color.success'))
      this.rateBtn(id, '模糊', $r('app.color.warning'))
      this.rateBtn(id, '不会', $r('app.color.danger'))
    }
  }

  @Builder rateBtn(id: string, label: string, color: ResourceColor) {
    Button(label)
      .fontSize(13)
      .height(34)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.ratings[id] === label ? color : $r('app.color.surface_variant'))
      .fontColor(this.ratings[id] === label ? $r('app.color.on_primary') : color)
      .borderRadius(RADIUS.pill)
      .onClick(() => this.onRate(id, label))
  }

  // 选套列表
  @Builder setItem(s: MockSet) {
    Row() {
      Column() {
        Text(s.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${s.questionIds.length} 题 · ${s.source}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (s.totalSpeak > 0) {
        Text(`建议 ${this.fmt(s.totalThink + s.totalSpeak)}`)
          .fontSize(12)
          .fontColor($r('app.color.brand'))
          .margin({ right: 8 })
      }
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_arrow'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .margin({ bottom: 8 })
    .onClick(() => this.onStartSet(s))
  }

  build() {
    Column() {
      if (this.phase === 'select') {
        // 顶部统计
        if (this.data) {
          Text(`真题模考 · 共 ${this.sets.length} 套（含 25 套强化训练 + 7 套历年真题）`)
            .fontSize(13)
            .fontColor($r('app.color.brand'))
            .margin({ top: 16, bottom: 6 })
        }
        // 顶部搜索框（搜真题 / 来源）
        TextInput({ placeholder: '搜索套题 / 来源，如：套题1、浚县', text: this.kw })
          .width('92%')
          .height(38)
          .fontSize(14)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: 14 })
          .margin({ top: 4, bottom: 10 })
          .onChange((v: string) => {
            this.kw = v;
          })
        // 随机单题入口
        Button('随机单题自测（快速热身）')
          .width('92%')
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .borderRadius(RADIUS.pill)
          .margin({ bottom: 12 })
          .onClick(() => this.onStartSingle())
        // 套题列表（受搜索过滤）
        List() {
          ForEach(this.filteredSets, (s: MockSet) => {
            ListItem() { this.setItem(s); }
          }, (s: MockSet): string => s.id)
        }
        .width('92%')
        .layoutWeight(1)
      } else if (this.phase === 'exam') {
        // 模考阶段：仅题目 + 计时 + 笔记，锁答案
        Column() {
          Row() {
            Button('‹ 返回选套')
              .fontSize(13)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.transparent'))   // 全透明背景（替代 Color.Transparent）
              .onClick(() => this.onBackToSelect())
            Column() {
              Text(`第 ${this.idx + 1} / ${this.qList.length} 题`)
                .fontSize(14)
                .fontColor($r('app.color.text_title'))
                .fontWeight(FontWeight.Medium)
              if (this.curSet) {
                Text(this.curSet.title)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 2 })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            // 分段计时：待机态→显示「开始答题」按钮；运行态→显示倒计时
            if (!this.timerStarted) {
              Button('开始答题')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .height(36)
                .backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.on_primary'))
                .borderRadius(RADIUS.pill)
                .onClick(() => this.startTimer())
            } else {
              Column() {
                Text(this.stage === 'think' ? '思考中' : '作答中')
                  .fontSize(11)
                  .fontColor(this.stage === 'think' ? $r('app.color.brand') : $r('app.color.warning'))
                  .margin({ bottom: 1 })
                if (this.remain >= 0) {
                  Text(this.fmt(this.remain))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_title'))
                } else {
                  Text(`超时 ${-this.remain}s`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.danger'))
                }
              }
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('92%')
          .margin({ top: 14, bottom: 10 })

          // 分段计时说明：本题思考→作答节奏提示
          Row({ space: 8 }) {
            Text(`本题：思考 ${this.fmt(this.thinkSec || 0)}`)
              .fontSize(12)
              .fontColor($r('app.color.brand'))
            Text('→')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            Text(`作答 ${this.fmt(this.speakSec || 0)}`)
              .fontSize(12)
              .fontColor($r('app.color.warning'))
            if (!this.timerStarted) {
              Text('（点击上方「开始答题」启动倒计时）')
                .fontSize(11)
                .fontColor($r('app.color.brand'))
            } else {
              Text('（时间到会振动提示）')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
          }
          .width('92%')
          .margin({ bottom: 8 })

          Scroll() {
            Column() {
              if (this.qList[this.idx]) {
                Text('【题目】')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.brand'))
                  .margin({ bottom: 6 })
                Text(this.qList[this.idx].prompt)
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(26)

                // 开口自测：录音 + 回放 + 计时（按当前题 id 存本机）
                RecorderBar({ qid: this.curId })

                Text('我的作答要点（可选，仅存本机，复盘时对照）')
                  .fontSize(13)
                  .fontColor($r('app.color.text_title'))
                  .margin({ top: 20, bottom: 6 })
                TextArea({
                  text: this.notes[this.curId] ?? '',
                  placeholder: '在此列出答题框架 / 关键词，交卷后可与参考答案对照'
                })
                  .fontSize(14)
                  .height(120)
                  .backgroundColor($r('app.color.surface'))
                  .borderRadius(RADIUS.md)
                  .onChange((v: string): void => {
                    this.onNoteChange(v);
                  })
              }
            }
            .width('92%')
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width('100%')

          Button(this.idx < this.qList.length - 1 ? '下一题' : '交卷，看参考答案')
            .width('92%')
            .height(46)
            .fontSize(16)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .margin({ bottom: 16 })
            .onClick(() => this.onNext())
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
      } else if (this.phase === 'review') {
        // 整卷复盘：逐题出参考答案 + 自评
        Column() {
          Row() {
            Button('‹ 选套')
              .fontSize(13)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.transparent'))
              .onClick(() => this.onBackToSelect())
            Text('整卷复盘')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text(`用时 ${this.fmt(this.elapsed)}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('92%')
          .margin({ top: 14, bottom: 8 })

          Scroll() {
            Column() {
              ForEach(this.qList, (q: Question, i: number) => {
                Column() {
                  Text(`第 ${i + 1} 题 · ${q.type}`)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_title'))
                    .margin({ bottom: 6 })
                  Text(q.prompt)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .lineHeight(22)
                    .margin({ bottom: 8 })

                  if (this.notes[q.id]) {
                    Text('我的作答要点')
                      .fontSize(13)
                      .fontColor($r('app.color.warning'))
                      .margin({ bottom: 2 })
                    Text(this.notes[q.id])
                      .fontSize(13)
                      .fontColor($r('app.color.text_body'))
                      .lineHeight(20)
                      .margin({ bottom: 8 })
                  }

                  // 本地语音识别转写：考生口述作答的文字版，对照逐字稿找差距
                  if (this.asrOf(q.id)) {
                    Text('我的口述转写（本地语音识别）')
                      .fontSize(13)
                      .fontColor($r('app.color.brand'))
                      .margin({ bottom: 2 })
                    Text(this.asrOf(q.id))
                      .fontSize(13)
                      .fontColor($r('app.color.text_body'))
                      .lineHeight(20)
                      .margin({ bottom: 8 })
                  }

                  Text('【参考答案 · 逐字稿】')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.brand'))
                    .margin({ bottom: 4 })
                  Text(q.answerScript)
                    .fontSize(14)
                    .fontColor($r('app.color.text_body'))
                    .lineHeight(22)
                    .margin({ bottom: 10 })

                  this.ratingRow(q.id)
                }
                .width('100%')
                .padding(14)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(RADIUS.md)
                .margin({ bottom: 12 })
                .alignItems(HorizontalAlign.Start)
              }, (q: Question): string => q.id)
            }
            .width('92%')
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width('100%')

          Button('查看练习报告')
            .width('92%')
            .height(46)
            .fontSize(16)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .margin({ bottom: 16 })
            .onClick(() => this.onToReport())
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
      } else {
        // 练习报告
        Column() {
          Row() {
            Button('‹ 选套')
              .fontSize(13)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.transparent'))
              .onClick(() => this.onBackToSelect())
            Text('练习报告')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Blank()
          }
          .width('92%')
          .margin({ top: 14, bottom: 10 })

          // 统计卡
          Row({ space: 10 }) {
            this.statCard('总用时', this.fmt(this.elapsed), $r('app.color.text_title'))
            this.statCard('掌握', `${this.masterCount}`, $r('app.color.success'))
            this.statCard('模糊', `${this.vagueCount}`, $r('app.color.warning'))
            this.statCard('不会', `${this.failCount}`, $r('app.color.danger'))
          }
          .width('92%')
          .margin({ bottom: 12 })

          Scroll() {
            Column() {
              ForEach(this.qList, (q: Question, i: number) => {
                Row() {
                  Text(`第 ${i + 1} 题`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width(52)
                  Text(q.title)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.ratingText(q.id))
                    .fontSize(12)
                    .fontColor(this.ratingColor(q.id))
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.surface'))
                .borderRadius(RADIUS.sm)
                .margin({ bottom: 6 })
              }, (q: Question): string => q.id)
            }
            .width('92%')
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width('100%')

          Button('再来一套')
            .width('92%')
            .height(46)
            .fontSize(16)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_primary'))
            .borderRadius(RADIUS.pill)
            .margin({ bottom: 16 })
            .onClick(() => this.onBackToSelect())
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  // 辅助：统计某评级数量
  private countRating(label: string): number {
    let c: number = 0;
    for (let i: number = 0; i < this.qList.length; i++) {
      if (this.ratings[this.qList[i].id] === label) c++;
    }
    return c;
  }

  // 辅助：获取评级的显示文字（避免 builder 内写 const）
  private ratingText(qid: string): string {
    const r: string = this.ratings[qid] || '未评';
    return r;
  }

  // 辅助：获取评级颜色（ResourceColor，随深浅模式切换）
  private ratingColor(qid: string): ResourceColor {
    const r: string = this.ratings[qid];
    if (r === '掌握') return $r('app.color.success');
    if (r === '模糊') return $r('app.color.warning');
    if (r === '不会') return $r('app.color.danger');
    return $r('app.color.text_tertiary');
  }

  @Builder statCard(label: string, value: string, color: ResourceColor) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2 })
    }
    .width('18%')
    .padding(10)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .alignItems(HorizontalAlign.Center)
  }
}

// 真题模考 Tab（档位 B）：选套 → 限时连做 → 交卷复盘 → 练习报告
// 对齐华图/粉笔逻辑：模考阶段锁答案，复盘才出【参考答案 · 逐字稿】，逐题自评（本地持久化）
// 顶部加搜索框搜真题；每完成一套写一条演练记录供「个人中心」读取
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Question, MockSet, PracticeSession } from '../model/Types';
import { preferences } from '@kit.ArkData';

const PREF_NAME: string = 'practice';

@Component
export struct PracticeView {
  @State data: AppData | null = null;
  @State sets: MockSet[] = [];
  @State phase: 'select' | 'exam' | 'review' | 'report' = 'select';
  @State curSet: MockSet | null = null;
  @State qList: Question[] = [];
  @State idx: number = 0;
  @State elapsed: number = 0;                 // 模考已用时（秒，正计时）
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
    const ctx = getContext(this) as common.UIAbilityContext;
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

  startTimer(): void {
    this.clearTimer();
    this.timer = setInterval((): void => { this.elapsed++; }, 1000);
  }

  startSet(s: MockSet): void {
    const qs: Question[] = DataStore.questionsOfSet(s.id);
    if (qs.length === 0) return;
    this.curSet = s;
    this.qList = qs;
    this.idx = 0;
    this.elapsed = 0;
    this.phase = 'exam';
    this.startTimer();
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
    this.phase = 'exam';
    this.startTimer();
  }

  next(): void {
    if (this.idx < this.qList.length - 1) {
      this.idx++;
    } else {
      this.submit();
    }
  }

  submit(): void {
    this.clearTimer();
    this.phase = 'review';
  }

  backToSelect(): void {
    this.clearTimer();
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
    for (let k = 0; k < keys.length; k++) {
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
    for (let k = 0; k < keys.length; k++) {
      nextN[keys[k]] = this.notes[keys[k]];
    }
    nextN[id] = v;
    this.notes = nextN;
    this.persistNote(id, v);
  }

  fmt(sec: number): string {
    const m: number = Math.floor(sec / 60);
    const s: number = sec % 60;
    return `${m}:${s < 10 ? '0' + s : '' + s}`;
  }

  private fmtDate(): string {
    const d: Date = new Date();
    const p2 = (n: number): string => (n < 10 ? '0' + n : '' + n);
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
      this.rateBtn(id, '掌握', '#1a7f37')
      this.rateBtn(id, '模糊', '#b8860b')
      this.rateBtn(id, '不会', '#c0392b')
    }
  }

  @Builder rateBtn(id: string, label: string, color: string) {
    Button(label)
      .fontSize(13)
      .height(34)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.ratings[id] === label ? color : '#EEF2F7')
      .fontColor(this.ratings[id] === label ? '#FFFFFF' : color)
      .borderRadius(17)
      .onClick(() => this.onRate(id, label))
  }

  // 选套列表
  @Builder setItem(s: MockSet) {
    Row() {
      Column() {
        Text(s.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1f2d3d')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${s.questionIds.length} 题 · ${s.source}`)
          .fontSize(12)
          .fontColor('#888')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (s.totalSpeak > 0) {
        Text(`建议 ${this.fmt(s.totalThink + s.totalSpeak)}`)
          .fontSize(12)
          .fontColor('#185FA5')
          .margin({ right: 8 })
      }
      Text('›')
        .fontSize(20)
        .fontColor('#CCC')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
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
            .fontColor('#185FA5')
            .margin({ top: 16, bottom: 6 })
        }
        // 顶部搜索框（搜真题 / 来源）
        TextInput({ placeholder: '搜索套题 / 来源，如：套题1、浚县', text: this.kw })
          .width('92%')
          .height(38)
          .fontSize(14)
          .backgroundColor('#FFFFFF')
          .borderRadius(19)
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
          .backgroundColor('#14385c')
          .fontColor('#FFFFFF')
          .borderRadius(20)
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
              .fontColor('#185FA5')
              .backgroundColor('#00000000')   // 全透明背景（替代 Color.Transparent）
              .onClick(() => this.onBackToSelect())
            Column() {
              Text(`第 ${this.idx + 1} / ${this.qList.length} 题`)
                .fontSize(14)
                .fontColor('#14385c')
                .fontWeight(FontWeight.Medium)
              if (this.curSet) {
                Text(this.curSet.title)
                  .fontSize(12)
                  .fontColor('#888')
                  .margin({ top: 2 })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            Text(`用时 ${this.fmt(this.elapsed)}`)
              .fontSize(14)
              .fontColor(this.elapsed > this.suggestedSec ? '#c0392b' : '#14385c')
              .fontWeight(FontWeight.Medium)
          }
          .width('92%')
          .margin({ top: 14, bottom: 10 })

          if (this.curSet && this.suggestedSec > 0) {
            Text(`本套建议总时长 ${this.fmt(this.suggestedSec)}（思考+作答），超时也无妨，重在模拟节奏`)
              .fontSize(12)
              .fontColor('#888')
              .width('92%')
              .margin({ bottom: 8 })
          }

          Scroll() {
            Column() {
              if (this.qList[this.idx]) {
                Text('【题目】')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#185FA5')
                  .margin({ bottom: 6 })
                Text(this.qList[this.idx].prompt)
                  .fontSize(16)
                  .fontColor('#1f2d3d')
                  .lineHeight(26)

                Text('我的作答要点（可选，仅存本机，复盘时对照）')
                  .fontSize(13)
                  .fontColor('#14385c')
                  .margin({ top: 20, bottom: 6 })
                TextArea({
                  text: this.notes[this.curId] ?? '',
                  placeholder: '在此列出答题框架 / 关键词，交卷后可与参考答案对照'
                })
                  .fontSize(14)
                  .height(120)
                  .backgroundColor('#FFFFFF')
                  .borderRadius(10)
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
            .backgroundColor('#185FA5')
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .margin({ bottom: 16 })
            .onClick(() => this.onNext())
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F7FA')
      } else if (this.phase === 'review') {
        // 整卷复盘：逐题出参考答案 + 自评
        Column() {
          Row() {
            Button('‹ 选套')
              .fontSize(13)
              .fontColor('#185FA5')
              .backgroundColor('#00000000')
              .onClick(() => this.onBackToSelect())
            Text('整卷复盘')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#14385c')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text(`用时 ${this.fmt(this.elapsed)}`)
              .fontSize(13)
              .fontColor('#888')
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
                    .fontColor('#14385c')
                    .margin({ bottom: 6 })
                  Text(q.prompt)
                    .fontSize(14)
                    .fontColor('#1f2d3d')
                    .lineHeight(22)
                    .margin({ bottom: 8 })

                  if (this.notes[q.id]) {
                    Text('我的作答要点')
                      .fontSize(13)
                      .fontColor('#b8860b')
                      .margin({ bottom: 2 })
                    Text(this.notes[q.id])
                      .fontSize(13)
                      .fontColor('#555')
                      .lineHeight(20)
                      .margin({ bottom: 8 })
                  }

                  Text('【参考答案 · 逐字稿】')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#185FA5')
                    .margin({ bottom: 4 })
                  Text(q.answerScript)
                    .fontSize(14)
                    .fontColor('#2c2c2a')
                    .lineHeight(22)
                    .margin({ bottom: 10 })

                  this.ratingRow(q.id)
                }
                .width('100%')
                .padding(14)
                .backgroundColor('#FFFFFF')
                .borderRadius(12)
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
            .backgroundColor('#14385c')
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .margin({ bottom: 16 })
            .onClick(() => this.onToReport())
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F7FA')
      } else {
        // 练习报告
        Column() {
          Row() {
            Button('‹ 选套')
              .fontSize(13)
              .fontColor('#185FA5')
              .backgroundColor('#00000000')
              .onClick(() => this.onBackToSelect())
            Text('练习报告')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#14385c')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Blank()
          }
          .width('92%')
          .margin({ top: 14, bottom: 10 })

          // 统计卡
          Row({ space: 10 }) {
            this.statCard('总用时', this.fmt(this.elapsed), '#14385c')
            this.statCard('掌握', `${this.masterCount}`, '#1a7f37')
            this.statCard('模糊', `${this.vagueCount}`, '#b8860b')
            this.statCard('不会', `${this.failCount}`, '#c0392b')
          }
          .width('92%')
          .margin({ bottom: 12 })

          Scroll() {
            Column() {
              ForEach(this.qList, (q: Question, i: number) => {
                Row() {
                  Text(`第 ${i + 1} 题`)
                    .fontSize(13)
                    .fontColor('#888')
                    .width(52)
                  Text(q.title)
                    .fontSize(13)
                    .fontColor('#1f2d3d')
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.ratingText(q.id))
                    .fontSize(12)
                    .fontColor(this.ratingColor(q.id))
                }
                .width('100%')
                .padding(10)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
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
            .backgroundColor('#185FA5')
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .margin({ bottom: 16 })
            .onClick(() => this.onBackToSelect())
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F7FA')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }

  // 辅助：统计某评级数量
  private countRating(label: string): number {
    let c: number = 0;
    for (let i = 0; i < this.qList.length; i++) {
      if (this.ratings[this.qList[i].id] === label) c++;
    }
    return c;
  }

  // 辅助：获取评级的显示文字（避免 builder 内写 const）
  private ratingText(qid: string): string {
    const r: string = this.ratings[qid] || '未评';
    return r;
  }

  // 辅助：获取评级颜色
  private ratingColor(qid: string): string {
    const r: string = this.ratings[qid];
    if (r === '掌握') return '#1a7f37';
    if (r === '模糊') return '#b8860b';
    if (r === '不会') return '#c0392b';
    return '#999';
  }

  @Builder statCard(label: string, value: string, color: string) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(12)
        .fontColor('#888')
        .margin({ top: 2 })
    }
    .width('18%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .alignItems(HorizontalAlign.Center)
  }
}

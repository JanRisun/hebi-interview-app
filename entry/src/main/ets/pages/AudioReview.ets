// 音频作答点评页：题目 + 答题（思考时间 + 答题音频）+ AI 评分 / 点评 / AI 润色 / 解析与示范
// 布局：BackHeader + 横向 sticky Tab 栏（随滚动常驻顶部）+ 纵向滚动卡片内容；点击 Tab 滚动到对应小节。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AnswerRecord, Question } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { CloudAsrHelper } from '../utils/CloudAsrHelper';
import { SparkAiHelper, AiReviewResult, AiDimension } from '../utils/SparkAiHelper';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';

const DOMAIN: number = 0x0001;
const TAG: string = 'AudioReview';

// 路由参数：题目 id（用于拉取题目内容作为「题目」「答题」小节）+ 答题页直接透传的作答数据
interface AudioReviewParam {
  id: string;
  thinkSec?: number;
  speakSec?: number;
  audioPath?: string;
}

@Component
export struct AudioReviewView {
  @Prop params: Object;
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  @Consume pageStack: NavPathStack;

  @State question: Question | null = null;
  @State record: AnswerRecord | null = null;             // 答题记录（思考时长 + 作答时长 + 音频路径）
  @State thinkSec: number = 0;                           // 思考时长（秒），从记录提取以保证响应式刷新
  @State speakSec: number = 0;                           // 作答时长（秒），从记录提取以保证响应式刷新
  @State transcriptText: string = '';                   // 语音转文字结果
  @State hasTranscript: boolean = false;                 // 是否存在转写文本
  @State transcribing: boolean = false;                  // 是否正在端侧生成转写（最佳努力）
  @State transcriptError: string = '';                   // 转写失败原因（用于在页面上提示，避免静默"暂无转写"）
  @State showTranscriptSheet: boolean = false;           // 「查看更多」弹层是否展开
  @State activeTab: number = 0;                          // 当前高亮的 tab
  @State sectionOffsets: number[] = [0, 0, 0, 0, 0, 0];  // 6 个小节相对 Scroll 内部的 yOffset

  @State foldExpanded: boolean = false;                 // 「解析与示范」长文本是否展开
  @State scriptNeedFold: boolean = false;               // 参考解析是否需要折叠（超出默认 8 行）
  @State scriptContentWidth: number = 0;                // 「解析与示范」卡片内文本可用宽度（vp），布局后获取

  // AI 答题点评（讯飞星火）相关状态
  @State aiLoading: boolean = false;                    // 是否正在生成 AI 点评
  @State aiError: string = '';                          // AI 点评失败原因
  @State aiDone: boolean = false;                        // 是否已生成 AI 点评
  @State aiScore: number = 0;                           // 综合分
  @State aiLevel: string = '';                          // 等级
  @State aiSummary: string = '';                        // 一句话总评
  @State aiDimensions: AiDimension[] = []; // 维度评分
  @State aiReview: string[] = [];                        // 点评段落
  @State aiTags: string[] = [];                          // 标签
  @State aiPolishBefore: string = '';                   // 润色前
  @State aiPolishAfter: string = '';                    // 润色后

  // 答题音频回放（与音频作答页一致的 AVPlayer 实现）
  @State playbackProgress: number = 0;                  // 回放进度（毫秒）
  @State playbackDuration: number = 0;                  // 回放总时长（毫秒）
  @State isPlaying: boolean = false;                    // 是否正在回放
  @State playbackCompleted: boolean = false;            // 是否已播完
  private avPlayer: media.AVPlayer | undefined = undefined;
  private playFile: fileIo.File | undefined = undefined;
  private pendingPlay: boolean = false;                 // 尚未 prepared 时用户点播放，挂起待 prepared 后自动播放
  private avState: string = '';

  private scroller: Scroller = new Scroller();
  private readonly tabs: string[] = ['题目', '答题', '得分', '点评', 'AI润色', '解析与示范'];

  async aboutToAppear(): Promise<void> {
    const p: AudioReviewParam | null = this.params as AudioReviewParam;
    if (!p || !p.id) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    await DataStore.load(ctx);
    this.question = DataStore.questionById(p.id) ?? null;

    // 优先使用路由参数直接透传的答题数据（音频作答页实时数据，最可靠，避免子组件内读取偏好存储失败）
    if (p.thinkSec !== undefined || p.speakSec !== undefined || p.audioPath) {
      this.thinkSec = p.thinkSec ?? 0;
      this.speakSec = p.speakSec ?? 0;
      this.record = {
        id: p.id,
        title: this.question ? this.question.title : '',
        thinkSec: this.thinkSec,
        speakSec: this.speakSec,
        date: '',
        audioPath: p.audioPath ?? ''
      };
      if (p.audioPath) {
        this.initPlayback(p.audioPath);
      }
      await this.loadTranscript(p.id, ctx);
      if (this.hasTranscript) {
        this.loadAiReview();
      }
      return;
    }

    // 兜底：从本地偏好存储读取（如通过其它入口进入点评页）
    try {
      const prefs = await preferences.getPreferences(ctx, 'practice');
      const raw: string = prefs.getSync('a_' + p.id, '') as string;
      if (raw) {
        const rec: AnswerRecord = JSON.parse(raw) as AnswerRecord;
        this.record = rec;
        this.thinkSec = rec.thinkSec ?? 0;
        this.speakSec = rec.speakSec ?? 0;
        if (rec.audioPath) {
          this.initPlayback(rec.audioPath);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'load record fail: %{public}s', err.message);
    }
    await this.loadTranscript(p.id, ctx);
    if (this.hasTranscript) {
      this.loadAiReview();
    }
  }

  // 加载语音转文字：优先读取作答页已落盘的 rec_<id>.txt；不存在时对录音做一次云侧 ASR（讯飞 IAT，需联网与正确密钥）
  private async loadTranscript(id: string, ctx: common.UIAbilityContext): Promise<void> {
    this.transcriptError = '';
    const path: string = ctx.filesDir + '/rec_' + id + '.txt';
    let text: string = '';
    try {
      text = fileIo.readTextSync(path);
    } catch (e) {
      // 无转写文件，忽略
    }
    if (text && text.length > 0) {
      this.transcriptText = text;
      this.hasTranscript = true;
      return;
    }
    // 文件不存在或为空 → 最佳努力：对录音做一次云侧语音转写
    if (this.record && this.record.audioPath) {
      this.transcribing = true;
      try {
        const result: string = await CloudAsrHelper.transcribe(this.record.audioPath);
        if (result && result.length > 0) {
          this.transcriptText = result;
          this.hasTranscript = true;
          try {
            const fd = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
            fileIo.writeSync(fd.fd, result);
            fileIo.closeSync(fd.fd);
          } catch (e) { /* ignore */ }
        } else {
          // 识别跑通但无文字（静音 / 录音无清晰人声）
          this.transcriptError = '转写未识别到文字（可能录音为静音或无人声），请重新录制，或在「开口自测」页手动录入转写稿。';
        }
      } catch (e) {
        const msg: string = (e as BusinessError)?.message || (e as Error)?.message || '未知错误';
        hilog.error(DOMAIN, TAG, 'lazy transcribe fail: %{public}s', msg);
        this.transcriptError = '转写失败：' + msg + '（云侧语音识别需联网且讯飞密钥正确；若提示鉴权失败，请检查 CloudAsrHelper.ets 顶部 APPID/APIKey/APISecret。可在「开口自测」页手动录入转写稿）';
      } finally {
        this.transcribing = false;
      }
    }
  }

  // 调用讯飞星火生成真实 AI 答题点评，并写入页面状态
  private loadAiReview(): void {
    if (!this.transcriptText || this.transcriptText.length === 0) {
      return; // 无转写稿则不调用星火，避免空稿请求与浪费额度
    }
    this.aiLoading = true;
    this.aiError = '';
    this.aiDone = false;
    const title: string = this.question ? this.question.title : '';
    const prompt: string = this.question ? this.question.prompt : '';
    const transcript: string = this.transcriptText;
    SparkAiHelper.reviewAnswer(title, prompt, transcript)
      .then((res: AiReviewResult): void => {
        this.aiScore = res.score;
        this.aiLevel = res.level;
        this.aiSummary = res.summary;
        this.aiDimensions = res.dimensions;
        this.aiReview = res.review;
        this.aiTags = res.tags;
        this.aiPolishBefore = res.polishBefore;
        this.aiPolishAfter = res.polishAfter;
        this.aiDone = true;
        this.aiLoading = false;
      })
      .catch((e: Error): void => {
        this.aiError = (e as BusinessError)?.message || e.message || '未知错误';
        this.aiLoading = false;
        hilog.error(DOMAIN, TAG, 'AI review fail: %{public}s', this.aiError);
      });
  }

  aboutToDisappear(): void {
    this.releasePlayback();
  }

  // 点击 Tab：滚动到对应小节。offset 由 onAreaChange 在布局后填充
  private scrollToTab(idx: number): void {
    this.activeTab = idx;
    const y: number = this.sectionOffsets[idx];
    if (y > 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: y - SPACE.sm });
    }
  }

  // 监听小节位置变化，把 yOffset 缓存下来供 scrollTo 使用
  private onSectionArea(idx: number, _oldArea: Area, newA: Area): void {
    const next: number[] = [...this.sectionOffsets];
    next[idx] = newA.position.y as number;
    this.sectionOffsets = next;
  }

  // 依据卡片实际宽度估算参考解析行数：中文为主，每行约容纳 (宽度/字号) 个字符；超过 8 行则显示折叠按钮
  private updateFold(): void {
    if (!this.question || this.scriptContentWidth <= 0) {
      this.scriptNeedFold = false;
      return;
    }
    const textWidth: number = this.scriptContentWidth - 2 * SPACE.lg; // 减去卡片左右内边距
    if (textWidth <= 0) {
      this.scriptNeedFold = false;
      return;
    }
    const charsPerLine: number = Math.max(1, Math.floor(textWidth / FONT.body));
    const lines: number = Math.ceil((this.question.answerScript?.length ?? 0) / charsPerLine);
    this.scriptNeedFold = lines > 8;
  }

  // 秒数格式化为 mm:ss
  private fmt(sec: number): string {
    const total: number = Math.max(0, Math.floor(sec ?? 0));
    const m: number = Math.floor(total / 60);
    const s: number = total % 60;
    return (m < 10 ? '0' + m : '' + m) + ':' + (s < 10 ? '0' + s : '' + s);
  }

  // ---- 答题音频回放：AVPlayer 播放本地 WAV（与音频作答页一致） ----
  private async initPlayback(path: string): Promise<void> {
    this.releasePlayback();
    try {
      const stat: fileIo.Stat = fileIo.statSync(path);
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      this.playFile = file;
      const player: media.AVPlayer = await media.createAVPlayer();
      this.avPlayer = player;

      player.on('error', (err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'avPlayer error: %{public}s', err.message);
      });

      player.on('stateChange', (state, reason): void => {
        this.avState = state;
        if (state === 'initialized') {
          try { player.prepare(); } catch (e) { /* ignore */ }
        } else if (state === 'prepared') {
          this.playbackDuration = player.duration;
          this.playbackCompleted = false;
          if (this.pendingPlay) {
            this.pendingPlay = false;
            try { player.play(); } catch (e) { /* ignore */ }
            this.isPlaying = true;
          }
        } else if (state === 'completed') {
          this.isPlaying = false;
          this.playbackCompleted = true;
          this.playbackProgress = this.playbackDuration;
        } else if (state === 'released') {
          this.avPlayer = undefined;
        }
      });

      player.on('timeUpdate', (time): void => {
        this.playbackProgress = time;
      });

      player.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'initPlayback fail: %{public}s', err.message);
    }
  }

  private releasePlayback(): void {
    this.isPlaying = false;
    this.pendingPlay = false;
    this.avState = '';
    if (this.avPlayer) {
      try {
        this.avPlayer.stop();
        this.avPlayer.release();
      } catch (e) { /* ignore */ }
      this.avPlayer = undefined;
    }
    if (this.playFile) {
      try { fileIo.closeSync(this.playFile.fd); } catch (e) { /* ignore */ }
      this.playFile = undefined;
    }
  }

  private togglePlayback(): void {
    try {
      const p = this.avPlayer;
      if (!p) return;
      if (this.isPlaying) {
        p.pause();
        this.isPlaying = false;
        return;
      }
      if (this.playbackCompleted) {
        p.seek(0);
        this.playbackProgress = 0;
        this.playbackCompleted = false;
      }
      if (this.avState !== 'prepared' && this.avState !== 'playing' && this.avState !== 'paused') {
        this.pendingPlay = true;
        return;
      }
      try { p.play(); } catch (e) { /* ignore */ }
      this.isPlaying = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'togglePlayback fail: %{public}s', err.message);
    }
  }

  private seekTo(ms: number): void {
    try {
      const p = this.avPlayer;
      if (!p) return;
      p.seek(ms);
      this.playbackProgress = ms;
      if (this.playbackCompleted) {
        this.playbackCompleted = false;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'seekTo fail: %{public}s', err.message);
    }
  }

  build() {
    Column() {
      // sticky：标题栏
      BackHeader({ title: '点评' })

      // sticky：横向 Tab 栏
      this.tabBar()

      // 滚动内容
      Scroll(this.scroller) {
        Column() {
          this.questionSection()
          this.answerSection()
          if (this.aiDone || this.aiLoading || this.aiError) {
            this.scoreSection()
            this.reviewSection()
            this.aiPolishSection()
          }
          this.analysisTranscriptSection()
        }
        .width('100%')
        .padding({ bottom: SPACE.xl + this.safeBottom })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor($r('app.color.background'))
      .onScroll(() => {
        // 滚动时根据当前位置自动高亮最接近的 tab
        const y: number = this.scroller.currentOffset().yOffset;
        let nearest: number = 0;
        let minDist: number = Number.MAX_VALUE;
        for (let i: number = 0; i < this.sectionOffsets.length; i++) {
          const d: number = Math.abs(this.sectionOffsets[i] - y);
          if (d < minDist) {
            minDist = d;
            nearest = i;
          }
        }
        if (nearest !== this.activeTab) {
          this.activeTab = nearest;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .padding({ top: this.safeTop })
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 「查看更多」转写弹层（底部抽屉，展示完整语音转文字结果）
    .bindSheet($$this.showTranscriptSheet, this.transcriptSheet, {
      height: '70%',
      dragBar: true,
      backgroundColor: $r('app.color.surface')
    })
  }

  // 「查看更多」弹层内容：完整转写文字（可滚动）
  @Builder transcriptSheet() {
    Column() {
      Row() {
        Text('语音转文字')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Blank()
        Text('✕')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.showTranscriptSheet = false;
          })
      }
      .width('100%')
      .margin({ bottom: SPACE.md })

      Scroll() {
        Text(this.transcriptText)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_body'))
          .lineHeight(22)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg + this.safeBottom })
  }

  // ---- 顶部 Tab 栏（横向滚动 + 选中高亮 + 品牌色下划线） ----
  @Builder tabBar() {
    Row() {
      Scroll() {
        Row({ space: SPACE.lg }) {
          ForEach(this.tabs, (label: string, idx: number): void => {
            this.tabItem(label, idx);
          })
        }
        .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.md, bottom: SPACE.md })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .border({
      width: { bottom: 1 },
      color: $r('app.color.divider')
    })
  }

  @Builder tabItem(label: string, idx: number) {
    Column() {
      Text(label)
        .fontSize(FONT.body)
        .fontWeight(this.activeTab === idx ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === idx ? $r('app.color.brand') : $r('app.color.text_secondary'))
      Row()
        .width(this.activeTab === idx ? 24 : 0)
        .height(3)
        .borderRadius(2)
        .margin({ top: 6 })
        .backgroundColor(this.activeTab === idx ? $r('app.color.brand') : Color.Transparent)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.scrollToTab(idx);
    })
  }

  // ---- 通用小节标题（小节卡片顶部，标题前加品牌色短横线） ----
  @Builder sectionTitle(label: string) {
    Row() {
      Row()
        .width(3)
        .height(14)
        .borderRadius(2)
        .backgroundColor($r('app.color.brand'))
        .margin({ right: SPACE.sm })
      Text(label)
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: SPACE.md })
  }

  // ---- 题目小节：题干 + 提示 ----
  @Builder questionSection() {
    Column() {
      this.sectionTitle('题目')
      Text(this.question ? this.question.title : '暂无题目内容')
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .margin({ bottom: SPACE.sm })
      Text(this.question ? this.question.prompt : '请确认题目数据是否正确加载。')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec0')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(0, oldA, newA);
    })
  }

  // ---- 答题小节：思考时间 + 作答时长 + 答题音频回放 ----
  @Builder answerSection() {
    Column() {
      this.sectionTitle('答题')
      // 思考时间 / 作答时长
      Row({ space: SPACE.xl }) {
        this.metaChip('思考时间', this.fmt(this.thinkSec))
        this.metaChip('作答时长', this.fmt(this.speakSec))
      }
      .margin({ bottom: SPACE.md })

      // 答题音频回放
      if (this.record && this.record.audioPath) {
        this.audioPlaybackBar()
      } else {
        Text('暂无答题音频')
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
      }

      // 语音转文字：最多两行 + 查看更多弹层
      if (this.hasTranscript) {
        Column() {
          Text('语音转文字')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 4 })
          Text(this.transcriptText)
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_body'))
            .lineHeight(22)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row() {
            Text('查看更多')
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.brand'))
            Text('›')
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.brand'))
              .margin({ left: 2 })
          }
          .margin({ top: SPACE.xs })
          .alignSelf(ItemAlign.End)
          .onClick(() => {
            this.showTranscriptSheet = true;
          })
        }
        .width('100%')
        .margin({ top: SPACE.sm })
      } else if (this.transcribing) {
        Text('转写生成中…')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.sm })
      } else if (this.transcriptError) {
        // 显示具体失败原因（云侧未开通 / 无网络 / 引擎初始化失败 / 无识别结果），避免静默"暂无"
        Text(this.transcriptError)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.danger'))
          .lineHeight(20)
          .width('100%')
          .margin({ top: SPACE.sm })
      } else {
        Text('暂无转写文字')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.sm })
      }
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec1')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(1, oldA, newA);
    })
  }

  // 音频回放条：左播放按钮 + 中间时间/进度（与音频作答页一致）
  @Builder audioPlaybackBar() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.isPlaying) {
          Row() {
            Column()
              .width(4)
              .height(16)
              .backgroundColor($r('app.color.on_primary'))
              .borderRadius(1)
              .margin({ right: 4 })
            Column()
              .width(4)
              .height(16)
              .backgroundColor($r('app.color.on_primary'))
              .borderRadius(1)
          }
        } else if (this.playbackCompleted) {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(20)
            .fontColor([$r('app.color.on_primary')])
            .scale({ x: 1.3, y: 1.3 })
        } else {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18)
            .fontColor([$r('app.color.on_primary')])
            .offset({ x: 1 })
        }
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.brand'))
      .onClick(() => {
        this.togglePlayback();
      })

      Column() {
        Row() {
          Text(this.fmt(Math.floor(this.playbackProgress / 1000)))
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_primary'))
            .margin({ right: SPACE.sm })
          Blank()
          Text(this.fmt(Math.max(0, Math.floor(this.playbackDuration / 1000))))
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .margin({ bottom: 4 })

        Slider({
          value: this.playbackProgress,
          min: 0,
          max: this.playbackDuration > 0 ? this.playbackDuration : 1,
          step: 100
        })
          .blockColor($r('app.color.brand'))
          .trackColor($r('app.color.brand_light'))
          .selectedColor($r('app.color.brand'))
          .trackThickness(3)
          .blockSize({ width: 10, height: 10 })
          .width('100%')
          .onChange((value: number): void => {
            this.seekTo(value);
          })
      }
      .layoutWeight(1)
      .margin({ left: SPACE.md, right: SPACE.md })
    }
    .width('100%')
    .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.md, bottom: SPACE.md })
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius(RADIUS.md)
    .alignItems(VerticalAlign.Center)
  }

  @Builder metaChip(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 得分小节：分数大字 + 等级 + 维度评分 ----
  @Builder scoreSection() {
    Column() {
      this.sectionTitle('得分')
      if (this.aiLoading && !this.aiDone) {
        Text('AI 点评生成中…')
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.aiError && !this.aiDone) {
        Text('AI 点评失败：' + this.aiError)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.danger'))
          .lineHeight(20)
          .width('100%')
      } else if (this.aiDone) {
        Row() {
          Column() {
            Text('' + this.aiScore)
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.brand'))
            Text('综合分')
              .fontSize(FONT.caption)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)

          Row()
            .width(1)
            .height(40)
            .backgroundColor($r('app.color.divider'))
            .margin({ left: SPACE.xl, right: SPACE.xl })

          Column() {
            Text(this.aiLevel)
              .fontSize(FONT.title)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
            Text(this.aiSummary)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
              .maxLines(2)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 维度评分
        Column() {
          ForEach(this.aiDimensions, (d: AiDimension, i: number): void => {
            this.scoreRow(d.label, d.ratio);
          }, (d: AiDimension, i: number): string => {
            return '' + i;
          })
        }
        .width('100%')
        .margin({ top: SPACE.md })
      }
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec2')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(2, oldA, newA);
    })
  }

  @Builder scoreRow(label: string, ratio: number) {
    Row() {
      Text(label)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
      // 进度条
      Row() {
        Row()
          .height('100%')
          .width(`${ratio * 100}%`)
          .backgroundColor($r('app.color.brand'))
          .borderRadius(3)
      }
      .width('50%')
      .height(6)
      .backgroundColor($r('app.color.surface_variant'))
      .borderRadius(3)
      .margin({ left: SPACE.md, right: SPACE.md })

      Text(`${Math.round(ratio * 100)}`)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.brand'))
        .fontWeight(FontWeight.Bold)
        .width(32)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .margin({ top: SPACE.sm })
  }

  // ---- 点评小节：AI 评语（多段）+ 标签 ----
  @Builder reviewSection() {
    Column() {
      this.sectionTitle('点评')
      if (this.aiLoading && !this.aiDone) {
        Text('AI 点评生成中…')
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.aiError && !this.aiDone) {
        Text('AI 点评失败：' + this.aiError)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.danger'))
          .lineHeight(20)
          .width('100%')
      } else if (this.aiDone) {
        ForEach(this.aiReview, (paragraph: string, i: number): void => {
          Text(paragraph)
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_body'))
            .lineHeight(22)
            .margin({ bottom: SPACE.sm })
            .width('100%')
        }, (paragraph: string, i: number): string => {
          return '' + i;
        })
        if (this.aiTags.length > 0) {
          Row({ space: SPACE.sm }) {
            ForEach(this.aiTags, (t: string, i: number): void => {
              this.tagChip(t);
            }, (t: string, i: number): string => {
              return '' + i;
            })
          }
          .margin({ top: SPACE.md })
        }
      }
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec3')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(3, oldA, newA);
    })
  }

  @Builder tagChip(text: string) {
    Text(text)
      .fontSize(FONT.caption)
      .fontColor($r('app.color.brand'))
      .padding({ left: SPACE.sm, right: SPACE.sm, top: 4, bottom: 4 })
      .borderRadius(RADIUS.pill)
      .backgroundColor($r('app.color.brand_light'))
  }

  // ---- AI 润色小节：润色前后对比 ----
  @Builder aiPolishSection() {
    Column() {
      this.sectionTitle('AI 润色')
      if (this.aiLoading && !this.aiDone) {
        Text('AI 润色生成中…')
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.aiError && !this.aiDone) {
        Text('AI 润色失败：' + this.aiError)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.danger'))
          .lineHeight(20)
          .width('100%')
      } else if (this.aiDone) {
        if (this.aiPolishBefore) {
          Text('润色前')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
          Text(this.aiPolishBefore)
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_body'))
            .lineHeight(22)
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
            .margin({ top: SPACE.xs, bottom: SPACE.md })
            .borderRadius(RADIUS.md)
            .backgroundColor($r('app.color.surface_variant'))
        }
        if (this.aiPolishAfter) {
          Text('润色后')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.brand'))
          Text(this.aiPolishAfter)
            .fontSize(FONT.body)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(22)
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
            .margin({ top: SPACE.xs })
            .borderRadius(RADIUS.md)
            .backgroundColor($r('app.color.brand_light'))
        }
      }
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec4')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(4, oldA, newA);
    })
  }

  // ---- 解析与示范小节：对应题目页底部「解析与示范」，内容取自题目 answerScript ----
  @Builder analysisTranscriptSection() {
    Column() {
      this.sectionTitle('解析与示范')
      // 参考解析（与题目页一致的展示：answerScript）
      Text('参考解析')
        .fontSize(FONT.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_title'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: SPACE.sm })
      // 主显示文本：默认 8 行，超出省略；展开后显示全文
      Text(this.question ? this.question.answerScript : '暂无解析内容')
        .fontSize(FONT.body)
        .fontColor($r('app.color.text_body'))
        .lineHeight(22)
        .width('100%')
        .alignSelf(ItemAlign.Start)
        .maxLines(this.foldExpanded ? 1000 : 8)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.scriptNeedFold) {
        Text(this.foldExpanded ? '收起' : '展开全文')
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.brand'))
          .margin({ top: SPACE.sm })
          .alignSelf(ItemAlign.End)
          .onClick(() => {
            this.foldExpanded = !this.foldExpanded;
          })
      }
    }
    .width('92%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.lg, bottom: SPACE.lg })
    .margin({ left: SPACE.md, right: SPACE.md, top: SPACE.md })
    .borderRadius(RADIUS.lg)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
    .id('sec5')
    .onAreaChange((oldA: Area, newA: Area): void => {
      this.onSectionArea(5, oldA, newA);
      this.scriptContentWidth = newA.width as number;
      this.updateFold();
    })
  }

}

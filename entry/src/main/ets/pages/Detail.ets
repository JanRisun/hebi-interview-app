import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AnswerRecord, Article, Question, Section } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { UserTagStore, PRESET_MARK_TAGS } from '../utils/UserTagStore';
import { ReaderIcon } from '../utils/SpeechReader';
import { BackHeader } from '../utils/BackHeader';
import { SectionTitle, HighlightText } from '../utils/Ui';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';

// 路由参数类型（规避 arkts-no-untyped-obj-literals）
interface DetailParam { id: string; kind: string; kw?: string; cat?: string }
interface AudioAnswerParam { id: string }
interface VideoAnswerParam { id: string }

@Component
export struct Detail {
  @State itemId: string = '';
  @State kind: string = 'article';
  @State article: Article | null = null;
  @State question: Question | null = null;
  @State showAnswer: boolean = false;   // 真题详情：参考答案默认隐藏，手动展开
  @State fav: boolean = false;
  @State userTags: string[] = [];       // 当前内容的用户自定义标签
  @State kw: string = '';                 // 搜索进入时透传的关键词，用于在正文/标题高亮
  @State practiceInfo: string = '未练习';   // 答题练习头部右侧展示：未练习 / 已自评 · YYYY-MM-DD
  @State showStartDialog: boolean = false; // 「开始答题」弹窗：选择音频/视频作答
  @Prop params: Object;                    // 路由参数：{ id, kind, kw? }（Navigation 经 routeMap 透传）
  @Consume pageStack: NavPathStack;

  // 加载令牌：仅应用最新一次 load 的结果，避免复用/快速切换时旧异步覆盖新内容
  private loadToken: number = 0;
  // 题库答题页（questionView）滚动控制器：开始答题按钮 / 解析与示范跳转
  private questionScroller: Scroller = new Scroller();

  // 悬浮「我的标记」按钮：位置、左右手偏好（'left' / 'right'）、子菜单展开状态
  private readonly FAB_SIZE: number = 56;
  private readonly FAB_MARGIN: number = 16;
  @State stackW: number = 0;            // 根容器宽度
  @State stackH: number = 0;            // 根容器高度
  @State fabInit: boolean = false;      // 是否已按当前容器尺寸初始化过位置
  @State fabX: number = 0;              // 悬浮按钮 x（相对根容器左上角）
  @State fabY: number = 0;              // 悬浮按钮 y
  @State fabSide: string = 'right';     // 默认右手（右下角）
  @State fabAnimating: boolean = false; // 是否启用位置平滑过渡（左右手切换时）
  @State showMenu: boolean = false;     // 是否展开打标记波轮
  private dragging: boolean = false;    // 是否正在拖动按钮
  private gripAvailable: boolean = false; // 设备是否支持「智感握姿」(操作手感知)
  // 智感握姿回调：系统上报当前触控操作手（左/右手），按钮自动换边
  private gripCallback: Callback<motion.OperatingHandStatus> = (data: motion.OperatingHandStatus): void => {
    if (data === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
      this.applyGripSide('left');
    } else if (data === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
      this.applyGripSide('right');
    }
  };
  private dragStartX: number = 0;
  private dragStartY: number = 0;

  aboutToAppear(): void {
    const s: string | undefined = AppStorage.get('fabMarkSide') as string | undefined;
    if (s === 'left' || s === 'right') this.fabSide = s;
    this.initGripSensing();   // 智感握姿：订阅系统操作手状态，自动识别左右手
    this.load();
  }

  aboutToDisappear(): void {
    if (this.gripAvailable) {
      try {
        motion.off('operatingHandChanged', this.gripCallback);
      } catch (err) {
        const error = err as BusinessError;
        console.warn('Failed off operatingHandChanged, code=' + error.code);
      }
    }
  }

  // 智感握姿：先用 getRecentOperatingHandStatus 取当前操作手，再订阅 operatingHandChanged。
  // 设备不支持(801)或权限不足(201)时退化为触摸位置启发式（senseSide）。
  private initGripSensing(): void {
    try {
      const recent: motion.OperatingHandStatus = motion.getRecentOperatingHandStatus();
      if (recent === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
        this.fabSide = 'left';
        AppStorage.set('fabMarkSide', 'left');
      } else if (recent === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
        this.fabSide = 'right';
        AppStorage.set('fabMarkSide', 'right');
      }
      motion.on('operatingHandChanged', this.gripCallback);
      this.gripAvailable = true;
      console.info('Grip sensing (operatingHandChanged) enabled');
    } catch (err) {
      const error = err as BusinessError;
      console.warn('Grip sensing unavailable, code=' + error.code);
      this.gripAvailable = false;
    }
  }

  // 应用系统识别到的握姿（左/右手），平滑把按钮换到对应侧
  private applyGripSide(side: string): void {
    if (this.dragging || this.showMenu) return;
    if (side === this.fabSide) return;
    this.fabSide = side;
    AppStorage.set('fabMarkSide', side);
    this.fabAnimating = true;
    this.fabX = side === 'right'
      ? (this.stackW - this.FAB_SIZE - this.FAB_MARGIN)
      : this.FAB_MARGIN;
  }

  // 兜底：Navigation 复用 NavDestination 实例时，onPageShow 仍会随显示触发，
  // 保证 itemId / 内容 / 用户标签始终与当前路由参数一致
  onPageShow(): void {
    this.load();
  }

  // 依据路由参数加载内容与其用户标签；全程使用局部 id，避免异步期间 this.itemId 被改写导致串数据
  private async load(): Promise<void> {
    const p = (this.params ?? {}) as Record<string, Object>;
    const id: string = (p['id'] as string) ?? '';
    const kind: string = (p['kind'] as string) ?? 'article';
    const kw: string = ((p['kw'] as string) ?? '').trim();
    const cat: string = (p['cat'] as string) ?? '';
    this.itemId = id;
    this.kind = kind;
    this.kw = kw;
    const token: number = ++this.loadToken;
    const ctx = getContext(this) as common.UIAbilityContext;
    await DataStore.load(ctx);
    // 兜底确保收藏存储就绪（启动链未建立时，详情页也能自愈，避免点击收藏崩溃）
    await FavStore.init(ctx);
    if (token !== this.loadToken) return;
    if (kind === 'article') {
      this.article = DataStore.articleById(id, cat) ?? null;
    } else {
      this.question = DataStore.questionById(id) ?? null;
      this.showAnswer = false;
      // 答题练习头部右侧展示：优先展示音频作答记录（思考/作答时长），
      // 其次展示 r_<id> 自评结果，都没有则显示「未练习」
      try {
        const prefs = await preferences.getPreferences(ctx, 'practice');
        const ansJson: string = prefs.getSync('a_' + id, '') as string;
        let info: string = '未练习';
        if (ansJson) {
          try {
            const a: AnswerRecord = JSON.parse(ansJson) as AnswerRecord;
            info = '已作答 · 思考 ' + this.fmtDur(a.thinkSec) + ' / 作答 ' + this.fmtDur(a.speakSec);
          } catch (e) { /* ignore */ }
        } else {
          const rating: string = prefs.getSync('r_' + id, '') as string;
          if (rating) {
            info = '已自评 · ' + this.todayStr();
          }
        }
        this.practiceInfo = info;
      } catch (e) {
        this.practiceInfo = '未练习';
      }
    }
    if (token !== this.loadToken) return;
    this.fav = await FavStore.has(id);
    if (token !== this.loadToken) return;
    this.userTags = await UserTagStore.getUserTags(id);
  }

  // 取 YYYY-MM-DD 形式的本地日期（用于答题练习头部右侧）
  private todayStr(): string {
    const d: Date = new Date();
    const y: number = d.getFullYear();
    const m: string = (d.getMonth() + 1) < 10 ? '0' + (d.getMonth() + 1) : '' + (d.getMonth() + 1);
    const day: string = d.getDate() < 10 ? '0' + d.getDate() : '' + d.getDate();
    return y + '-' + m + '-' + day;
  }

  // 秒数格式化（用于答题练习头部：思考/作答时长）
  private fmtDur(s: number): string {
    const total: number = Math.max(0, Math.floor(s));
    const m: number = Math.floor(total / 60);
    const ss: number = total % 60;
    return m > 0 ? `${m}分${ss}秒` : `${ss}秒`;
  }

  private async toggleFav(): Promise<void> {
    try {
      this.fav = await FavStore.toggle(this.itemId);
    } catch (e) {
      // 收藏存储异常时仅给出反馈，不向上抛导致 app 崩溃
      console.error('toggleFav failed:', JSON.stringify(e));
    }
  }

  // 切换预设标记（已加则移除，未加则添加）
  private async togglePreset(p: string): Promise<void> {
    if (this.userTags.includes(p)) {
      this.userTags = await UserTagStore.removeTag(this.itemId, p);
    } else {
      this.userTags = await UserTagStore.addTag(this.itemId, p);
    }
  }

  // 题库答题页：导航栏右侧图标——收藏
  @Builder favAction() {
    Text(this.fav ? '★' : '☆')
      .fontSize(FONT.title)
      .fontColor(this.fav ? $r('app.color.favorite') : $r('app.color.text_tertiary'))
      .onClick(() => this.toggleFav())
  }

  // 悬浮「我的标记」主按钮（无子菜单，菜单已提至根层避免裁切）
  @Builder fabButton() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        // 同一字形：默认 '+'，展开时旋转 45° 变为 '×'（大小一致，带旋转动画）
        Text('+')
          .fontSize(26)
          .fontColor($r('app.color.on_primary'))
          .rotate({ angle: this.showMenu ? 45 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
        if (!this.showMenu && this.userTags.length > 0) {
          Text(`${this.userTags.length}`)
            .fontSize(11)
            .fontColor($r('app.color.on_primary'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(10)
            .padding({ left: 5, right: 5 })
            .position({ x: 30, y: -4 })
        }
      }
      .width(this.FAB_SIZE)
      .height(this.FAB_SIZE)
    }
    .width(this.FAB_SIZE)
    .height(this.FAB_SIZE)
    .backgroundColor($r('app.color.brand'))
    .borderRadius(this.FAB_SIZE / 2)
    .shadow({ radius: 12, color: $r('app.color.card_stroke'), offsetY: 3 })
    .scale({ x: this.showMenu ? 1.12 : 1, y: this.showMenu ? 1.12 : 1 })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .position({ x: this.fabX, y: this.fabY })
    .animation(this.fabAnimating ? { duration: 200, curve: Curve.EaseOut } : { duration: 0 })
    // 点击直接展开/收起菜单（不再依赖拖拽位移判断，避免灵敏度问题）
    .onClick(() => {
      this.showMenu = !this.showMenu;
    })
    // 拖拽手势：距离阈值抬高，不与点击冲突；拖拽时自动收起菜单
    .gesture(
      PanGesture({ distance: 10 })
        .onActionStart(() => {
          this.showMenu = false;
          this.dragging = true;
          this.fabAnimating = false;
          this.dragStartX = this.fabX;
          this.dragStartY = this.fabY;
        })
        .onActionUpdate((e: GestureEvent) => {
          const leftBound: number = this.FAB_MARGIN;
          const rightBound: number = this.stackW - this.FAB_SIZE - this.FAB_MARGIN;
          const topBound: number = this.safeTop + this.FAB_MARGIN;
          const bottomBound: number = this.stackH - this.FAB_SIZE - this.safeBottom - this.FAB_MARGIN;
          this.fabX = this.clamp(this.dragStartX + e.offsetX, leftBound, rightBound);
          this.fabY = this.clamp(this.dragStartY + e.offsetY, topBound, bottomBound);
        })
        .onActionEnd(() => {
          this.dragging = false;
          this.snapToEdge();
        })
    )
  }

  // 将悬浮按钮吸附到最近的水平边缘（左/右），并记忆偏好（左/右手）
  private snapToEdge(): void {
    const leftBound: number = this.FAB_MARGIN;
    const rightBound: number = this.stackW - this.FAB_SIZE - this.FAB_MARGIN;
    if (this.fabX + this.FAB_SIZE / 2 < this.stackW / 2) {
      this.fabSide = 'left';
      this.fabX = leftBound;
    } else {
      this.fabSide = 'right';
      this.fabX = rightBound;
    }
    AppStorage.set('fabMarkSide', this.fabSide);
  }

  // 兜底：设备不支持「智感握姿」时，仍按内容区触摸位置识别左右手
  private senseSide(x: number): void {
    if (this.gripAvailable) return;   // 有系统握姿识别则不再用启发式
    if (this.dragging || this.showMenu) return;
    const side: string = x > this.stackW / 2 ? 'right' : 'left';
    if (side === this.fabSide) return;
    this.fabSide = side;
    AppStorage.set('fabMarkSide', side);
    this.fabAnimating = true;
    this.fabX = side === 'right'
      ? (this.stackW - this.FAB_SIZE - this.FAB_MARGIN)
      : this.FAB_MARGIN;
  }

  private clamp(v: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, v));
  }

  // 标签弹窗内的单个标签按钮：选中高亮，点击切换
  @Builder tagButton(tag: string) {
    Button(tag)
      .fontSize(13)
      .fontColor(this.userTags.includes(tag) ? $r('app.color.on_primary') : $r('app.color.text_primary'))
      .backgroundColor(this.userTags.includes(tag) ? $r('app.color.brand') : $r('app.color.surface'))
      .border({ width: this.userTags.includes(tag) ? 0 : 1, color: $r('app.color.card_stroke') })
      .borderRadius(18)
      .height(36)
      .padding({ left: 14, right: 14 })
      .margin(4)
      .onClick(() => { this.togglePreset(tag); })
  }

  @Builder articleView() {
    Scroll() {
      Column() {
        // 大标题已上移至顶部 BackHeader（过长省略），此处不再重复
        HighlightText({ text: this.article!.category, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), baseWeight: FontWeight.Normal })
          .margin({ bottom: SPACE.sm })
        // 标签行：全部展示，自动换行
        if (this.article!.tags !== undefined && this.article!.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.article!.tags, (t: string) => {
              Text(t)
                .fontSize(FONT.caption)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.xs, right: SPACE.xs })
            }, (t: string) => t)
          }
          .width('100%')
          .margin({ bottom: SPACE.md })
        }
        // 语音播报：整篇知识点（标题 + 各小节标题与正文）
        Row() {
          ReaderIcon({
            readId: this.itemId + ':full',
            title: this.article!.title,
            text: this.article!.title + '。' +
              this.article!.sections.map((s: Section) => (s.heading ? s.heading + '。' : '') + s.body).join('。'),
            label: '朗读全文'
          })
        }
        .margin({ bottom: SPACE.md })
        ForEach(this.article!.sections, (s: Section) => {
          Column() {
            if (s.heading) {
              HighlightText({ text: s.heading, kw: this.kw, fontSize: FONT.title, baseColor: $r('app.color.brand'), baseWeight: FontWeight.Medium })
                .margin({ top: SPACE.md, bottom: SPACE.xs })
            }
            HighlightText({ text: s.body, kw: this.kw, fontSize: FONT.bodySm, baseColor: $r('app.color.text_body'), baseWeight: FontWeight.Normal })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }, (s: Section) => s.heading + s.body.slice(0, 10))
      }
      .width('92%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .padding({ bottom: SPACE.lg })
      .constraintSize({ minHeight: '100%' })
    }
    .contentStartOffset(0)
    .layoutWeight(1)
    .width('100%')
  }

  @Builder questionView() {
    Scroll(this.questionScroller) {
      Column() {
        // 1. 题干区：结构化小标签 + 标题 + 案例内容 + 标签 + 朗读题目
        //    结构化标签：题型（如「综合分析类」），灰色小芯片风格
        Text(this.question!.type)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_variant'))
          .borderRadius(RADIUS.sm)
          .padding({ left: SPACE.sm, right: SPACE.sm, top: 2, bottom: 2 })
          .margin({ bottom: SPACE.sm })
          .alignSelf(ItemAlign.Start)
        // 题目标题（大号粗体）
        HighlightText({ text: this.question!.title, kw: this.kw, fontSize: FONT.display, baseColor: $r('app.color.text_title'), baseWeight: FontWeight.Bold })
          .margin({ bottom: SPACE.sm })
        // 案例内容（题干）
        HighlightText({ text: this.question!.prompt, kw: this.kw, fontSize: FONT.bodySm, baseColor: $r('app.color.text_body'), baseWeight: FontWeight.Normal })
        // 真题标签行
        if (this.question!.tags !== undefined && this.question!.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.question!.tags, (t: string) => {
              Text(t)
                .fontSize(FONT.caption)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.sm, right: SPACE.xs })
            }, (t: string) => t)
          }
          .width('100%')
          .margin({ top: SPACE.sm })
        }
        // 朗读题目
        Row() {
          ReaderIcon({
            readId: this.itemId + ':q',
            title: this.question!.title,
            text: this.question!.prompt,
            label: '朗读题目'
          })
        }
        .margin({ top: SPACE.sm })

        // 2. 答题练习区：左侧「答题练习」标题，右侧练习状态；下方红色「开始答题」CTA
        Column() {
          Row() {
            Text('答题练习')
              .fontSize(FONT.title)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
            Blank()
            Text(this.practiceInfo)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: SPACE.lg, bottom: SPACE.sm })

          // 开始答题按钮：红色全宽 CTA，点击弹出「选择答题方式」弹窗（音频/视频）
          Button('开始答题')
            .width('100%')
            .height(48)
            .fontSize(FONT.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_primary'))
            .backgroundColor($r('app.color.danger'))
            .borderRadius(RADIUS.lg)
            .onClick(() => {
              this.showStartDialog = true;
            })
        }
        .width('100%')
        .margin({ top: SPACE.md, bottom: SPACE.md })
        .alignItems(HorizontalAlign.Start)

        // 3. 解析与示范：分段卡片（参考解析 / 知识拓展 / 来源）
        Column() {
          Text('解析与示范')
            .fontSize(FONT.title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
            .margin({ top: SPACE.lg, bottom: SPACE.md })
            .alignSelf(ItemAlign.Start)

          // 4.1 参考解析（带朗读）
          Column() {
            Row() {
              Text('📝 参考解析')
                .fontSize(FONT.body)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_title'))
              Blank()
              ReaderIcon({
                readId: this.itemId + ':ans',
                title: this.question!.title + ' · 参考解析',
                text: this.question!.answerScript,
                label: '朗读解析'
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: SPACE.sm })
            HighlightText({ text: this.question!.answerScript, kw: this.kw, fontSize: FONT.bodySm, baseColor: $r('app.color.text_body'), baseWeight: FontWeight.Normal })
          }
          .width('100%')
          .padding(SPACE.md)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.md)
          .margin({ bottom: SPACE.sm })
          .alignItems(HorizontalAlign.Start)

          // 4.2 知识拓展（标签 chip 列表）
          Column() {
            Text('💡 知识拓展')
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title'))
              .margin({ bottom: SPACE.sm })
              .alignSelf(ItemAlign.Start)
            if (this.question!.tags !== undefined && this.question!.tags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.question!.tags, (t: string) => {
                  Text(t)
                    .fontSize(FONT.caption)
                    .fontColor($r('app.color.brand'))
                    .backgroundColor($r('app.color.tag_bg'))
                    .borderRadius(RADIUS.pill)
                    .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.xs, bottom: SPACE.xs })
                    .margin({ top: SPACE.xs, right: SPACE.xs, bottom: SPACE.xs })
                }, (t: string) => t)
              }
              .width('100%')
            } else {
              Text('暂无拓展标签')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.text_tertiary'))
            }
          }
          .width('100%')
          .padding(SPACE.md)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.md)
          .margin({ bottom: SPACE.sm })
          .alignItems(HorizontalAlign.Start)

          // 4.3 来源
          Column() {
            Text('📚 来源')
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title'))
              .margin({ bottom: SPACE.sm })
              .alignSelf(ItemAlign.Start)
            Text(this.question!.source)
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.text_body'))
              .lineHeight(22)
          }
          .width('100%')
          .padding(SPACE.md)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.md)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('92%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .padding({ bottom: SPACE.lg })
      .constraintSize({ minHeight: '100%' })
    }
    .layoutWeight(1)
    .width('100%')
  }

  // 「开始答题」弹窗：选择答题方式 → 音频作答（跳 AudioAnswer 页）/ 视频作答（暂未实现，给出 toast）
  @Builder startDialogBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明遮罩：点击关闭弹窗
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => { this.showStartDialog = false; })

      // 弹窗主体（白底圆角卡片，两张方式卡片 + 标题）
      Column() {
        Text('选择答题方式')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .margin({ top: SPACE.md, bottom: SPACE.lg })

        Row({ space: SPACE.md }) {
          // 音频作答卡片
          Column() {
            Column() {
              Text('🎙️')
                .fontSize(44)
            }
            .width(120)
            .height(100)
            .borderRadius(RADIUS.lg)
            .backgroundColor('#FFE8E1')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: SPACE.sm })
            Text('音频作答')
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .layoutWeight(1)
          .padding(SPACE.md)
          .borderRadius(RADIUS.lg)
          .backgroundColor('#FFEDE5')
          .onClick(() => {
            this.showStartDialog = false;
            // 跳转到音频作答页：仅当是真题且已加载
            if (this.question) {
              const p: AudioAnswerParam = { id: this.question.id };
              this.pageStack.pushPathByName('AudioAnswer', p);
            }
          })

          // 视频作答卡片（暂未实现，点击关闭弹窗 + 给出 toast 提示）
          Column() {
            Column() {
              Text('🎥')
                .fontSize(44)
            }
            .width(120)
            .height(100)
            .borderRadius(RADIUS.lg)
            .backgroundColor('#FFF6D9')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: SPACE.sm })
            Text('视频作答')
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .layoutWeight(1)
          .padding(SPACE.md)
          .borderRadius(RADIUS.lg)
          .backgroundColor('#FFF8E5')
          .onClick(() => {
            this.showStartDialog = false;
            // 跳转到视频作答页：仅当是真题且已加载
            if (this.question) {
              const p: VideoAnswerParam = { id: this.question.id };
              this.pageStack.pushPathByName('VideoAnswer', p);
            }
          })
        }
        .width('100%')
        .padding({ left: SPACE.md, right: SPACE.md, bottom: SPACE.lg })
      }
      .width('88%')
      .borderRadius(RADIUS.xl)
      .backgroundColor($r('app.color.surface'))
      .padding({ top: SPACE.sm, bottom: SPACE.sm })
    }
    .width('100%')
    .height('100%')
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    // 朗读改用系统朗读控件 TextReader（自带悬浮播控面板），页面内不再自绘悬浮按钮
    Stack({ alignContent: Alignment.TopStart }) {
      // 主内容（头部 + 可滚动详情）
      Column() {
        // 用 Column 包裹 BackHeader，避免 @BuilderParam 组件无法直挂 margin
        Column() {
          BackHeader({
            title: this.kind === 'article' ? (this.article?.title ?? '知识点') : '真题详情',
            showAction: true,
            // 以「值传递」形式传入，确保 builder 内的 this 仍指向 Detail（按引用传递会被子组件 this 覆盖，导致 this.toggleFav 为 undefined 而崩溃）
            action: (): void => { this.favAction() }
          })
        }
        .margin({ top: this.safeTop })
        .width('100%')

        if (this.article) {
          this.articleView()
        } else if (this.question) {
          this.questionView()
        } else {
          Text('加载中…')
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_secondary'))
            .margin(SPACE.xl)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      .justifyContent(FlexAlign.Start)
      // 详情页是整屏 NavDestination；进入后首页（含悬浮 Tab 栏）已被隐藏。
      // 底部除系统安全区外，额外留白避免内容被屏幕圆角切割（同时避让右下角悬浮按钮）
      .padding({ bottom: this.safeBottom + SPACE.lg })
      // 内容区触摸：识别左右手（按按下点 x 落在屏幕哪一侧）
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.senseSide(e.touches[0].x);
        }
      })

      // 展开子菜单时的遮罩：点击空白处收起（必须在波轮圆钮下方渲染，
      // 否则透明遮罩会拦截圆钮的点击、并且遮在圆钮之上使其“点不中、看着像显示不出”）
      if (this.showMenu) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.transparent'))
          .onClick(() => { this.showMenu = false; })
      }

      // 标签弹窗：悬浮按钮上方的圆角卡片（上方优先，空间不够则弹到下方）
      if (this.showMenu) {
        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(PRESET_MARK_TAGS, (tag: string) => {
              this.tagButton(tag)
            }, (tag: string) => tag)
          }
          .width('100%')
        }
        .width(240)
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .shadow({ radius: 16, color: '#1A000000', offsetY: 4 })
        .position({
          x: this.clamp(this.fabX + this.FAB_SIZE / 2 - 120, 8, this.stackW - 248),
          y: this.fabY > 180 ? this.fabY - 160 : this.fabY + this.FAB_SIZE + 12
        })
        .transition(TransitionEffect.scale({ x: 0.8, y: 0.8 })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: 200, curve: Curve.EaseOut }))
      }

      // 悬浮「我的标记」主按钮（点击展开、拖拽移动、智感握姿自动换边）
      this.fabButton()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 「开始答题」弹窗：选择音频/视频作答方式（半透明遮罩 + 居中卡片）
    .bindContentCover(this.showStartDialog, this.startDialogBuilder, {
      modalTransition: ModalTransition.DEFAULT,
      backgroundColor: '#00000000'
    })
    .onAreaChange((_old: Area, nw: Area) => {
      this.stackW = nw.width as number;
      this.stackH = nw.height as number;
      // 首次拿到容器尺寸时按左右手偏好放置到对应底角
      if (!this.fabInit && this.stackW > 0 && this.stackH > 0) {
        this.fabInit = true;
        this.fabY = this.stackH - this.FAB_SIZE - this.safeBottom - this.FAB_MARGIN;
        this.fabX = this.fabSide === 'right'
          ? (this.stackW - this.FAB_SIZE - this.FAB_MARGIN)
          : this.FAB_MARGIN;
      }
    })
  }
}

// 预览专用：mock 详情页，Previewer 无需 router/DataStore/FavStore
@Preview
@Component
struct DetailPreview {
  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
        Text('知识点详情')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 12 })
        Blank()
        Text('⭐')
          .fontSize(18)
      }
      .width('100%')
      .padding(SPACE.lg)

      Text('综合分析类答题框架')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .padding({ left: SPACE.lg, right: SPACE.lg })

      Text('表态—分析—对策')
        .fontSize(13)
        .fontColor($r('app.color.brand'))
        .padding({ left: SPACE.lg, right: SPACE.lg, top: 6 })

      Column() {
        Text('一、表态环节')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 6 })
        Text('明确立场 + 一句话概括本质，开门见山。')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
      }
      .width('90%')
      .padding(SPACE.lg)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.md)
      .margin({ top: SPACE.md, left: SPACE.lg, right: SPACE.lg })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Article, Question, Section } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { UserTagStore } from '../utils/UserTagStore';
import { RecorderBar } from '../utils/RecorderBar';
import { ReaderIcon } from '../utils/SpeechReader';
import { BackHeader } from '../utils/BackHeader';
import { SectionTitle, TagChip, HighlightText } from '../utils/Ui';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

// 预设快捷标记（点击切换：未加→添加，已加→移除）
const PRESET_TAGS: string[] = ['已背', '易错', '重点', '常考', '待复习', '难点'];

@Component
export struct Detail {
  @State itemId: string = '';
  @State kind: string = 'article';
  @State article: Article | null = null;
  @State question: Question | null = null;
  @State showAnswer: boolean = false;   // 真题详情：参考答案默认隐藏，手动展开
  @State fav: boolean = false;
  @State userTags: string[] = [];       // 当前内容的用户自定义标签
  @State customInput: string = '';       // 自定义标签输入框
  @State kw: string = '';                 // 搜索进入时透传的关键词，用于在正文/标题高亮
  @Prop params: Object;                    // 路由参数：{ id, kind, kw? }（Navigation 经 routeMap 透传）

  // 加载令牌：仅应用最新一次 load 的结果，避免复用/快速切换时旧异步覆盖新内容
  private loadToken: number = 0;

  aboutToAppear(): void {
    this.load();
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
    this.itemId = id;
    this.kind = kind;
    this.kw = kw;
    const token: number = ++this.loadToken;
    const ctx = getContext(this) as common.UIAbilityContext;
    await DataStore.load(ctx);
    if (token !== this.loadToken) return;
    if (kind === 'article') {
      this.article = DataStore.articleById(id) ?? null;
    } else {
      this.question = DataStore.questionById(id) ?? null;
      this.showAnswer = false;
    }
    if (token !== this.loadToken) return;
    this.fav = await FavStore.has(id);
    if (token !== this.loadToken) return;
    this.userTags = await UserTagStore.getUserTags(id);
  }

  private async toggleFav(): Promise<void> {
    this.fav = await FavStore.toggle(this.itemId);
  }

  // 切换预设标记（已加则移除，未加则添加）
  private async togglePreset(p: string): Promise<void> {
    if (this.userTags.includes(p)) {
      this.userTags = await UserTagStore.removeTag(this.itemId, p);
    } else {
      this.userTags = await UserTagStore.addTag(this.itemId, p);
    }
  }

  // 移除一个用户标签（点击当前标签）
  private async removeUserTag(t: string): Promise<void> {
    this.userTags = await UserTagStore.removeTag(this.itemId, t);
  }

  // 添加自定义标签
  private async addCustomTag(): Promise<void> {
    const t: string = this.customInput.trim();
    if (!t) return;
    this.userTags = await UserTagStore.addTag(this.itemId, t);
    this.customInput = '';
  }

  // 我的标记管理区：当前标签(点按移除) + 预设快捷 + 自定义输入（卡片化）
  @Builder userTagSection() {
    Column() {
      SectionTitle({ title: '我的标记' })

      // 已添加的标签：点击移除
      if (this.userTags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.userTags, (t: string) => {
            Row() {
              Text(t)
                .fontSize(FONT.caption)
                .fontColor($r('app.color.on_primary'))
              Text('✕')
                .fontSize(FONT.caption)
                .fontColor($r('app.color.on_primary'))
                .margin({ left: 4 })
            }
            .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
            .backgroundColor($r('app.color.brand'))
            .borderRadius(RADIUS.sm)
            .margin({ top: SPACE.xs, right: SPACE.xs })
            .onClick(() => this.removeUserTag(t))
          }, (t: string) => t)
        }
        .width('100%')
        .margin({ bottom: SPACE.xs })
      } else {
        Text('尚未标记，点击下方快速添加')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_tertiary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: SPACE.xs })
      }

      // 预设快捷标签：点击切换
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PRESET_TAGS, (p: string) => {
          TagChip({ text: p, selected: this.userTags.includes(p), onTap: () => { this.togglePreset(p); } })
            .margin({ top: SPACE.xs, right: SPACE.xs })
        }, (p: string) => p)
      }
      .width('100%')
      .margin({ bottom: SPACE.sm })

      // 自定义标签输入
      Row() {
        TextInput({ placeholder: '自定义标签，如：必考', text: this.customInput })
          .layoutWeight(1)
          .height(36)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(RADIUS.pill)
          .padding({ left: SPACE.md })
          .onChange((v: string) => { this.customInput = v; })
        Button('添加')
          .height(36)
          .margin({ left: SPACE.sm })
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_primary'))
          .borderRadius(RADIUS.pill)
          .onClick(() => this.addCustomTag())
      }
      .width('100%')
      .margin({ bottom: SPACE.md })
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder articleView() {
    Scroll() {
      Column() {
        HighlightText({ text: this.article!.title, kw: this.kw, fontSize: FONT.display, baseColor: $r('app.color.text_title'), baseWeight: FontWeight.Bold })
          .margin({ bottom: SPACE.sm })
        HighlightText({ text: this.article!.category, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), baseWeight: FontWeight.Normal })
          .margin({ bottom: SPACE.xs })
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
        // 我的标记（用户自定义标签，持久化）
        this.userTagSection()
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
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder questionView() {
    Scroll() {
      Column() {
        HighlightText({ text: this.question!.title, kw: this.kw, fontSize: FONT.display, baseColor: $r('app.color.text_title'), baseWeight: FontWeight.Bold })
          .margin({ bottom: SPACE.sm })
        Row() {
          Text(this.question!.type)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.tag_bg'))
            .borderRadius(RADIUS.sm)
            .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
          HighlightText({ text: this.question!.source, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), baseWeight: FontWeight.Normal })
            .margin({ left: SPACE.sm })
        }.margin({ bottom: SPACE.xs })
        // 真题标签行：全部展示，自动换行
        if (this.question!.tags !== undefined && this.question!.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.question!.tags, (t: string) => {
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
        // 语音播报：题目
        Row() {
          ReaderIcon({
            readId: this.itemId + ':q',
            title: this.question!.title,
            text: this.question!.prompt,
            label: '朗读题目'
          })
        }
        .margin({ bottom: SPACE.md })
        // 我的标记（用户自定义标签，持久化）
        this.userTagSection()
        SectionTitle({ title: '题目' })
          .margin({ top: SPACE.sm, bottom: SPACE.xs })
        HighlightText({ text: this.question!.prompt, kw: this.kw, fontSize: FONT.bodySm, baseColor: $r('app.color.text_body'), baseWeight: FontWeight.Normal })
          .margin({ bottom: SPACE.md })
        // 开口自测：录音 + 回放 + 计时（按当前题 id 存本机）
        RecorderBar({ qid: this.itemId })
        if (this.showAnswer) {
          Row() {
            SectionTitle({ title: '参考答案 · 逐字稿' }) {
              ReaderIcon({
                readId: this.itemId + ':ans',
                title: this.question!.title + ' · 参考答案',
                text: this.question!.answerScript,
                label: '朗读解析'
              })
            }
          }
          .width('100%')
          .margin({ top: SPACE.sm, bottom: SPACE.xs })
          HighlightText({ text: this.question!.answerScript, kw: this.kw, fontSize: FONT.bodySm, baseColor: $r('app.color.text_body'), baseWeight: FontWeight.Normal })
        } else {
          Button('查看参考答案（逐字稿）')
            .onClick(() => { this.showAnswer = true; })
            .backgroundColor($r('app.color.brand'))
            .margin({ top: SPACE.xs, bottom: SPACE.xs })
          Text('先自测口述，再对照参考答案')
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: SPACE.xs })
        }
      }
      .width('92%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    // 朗读改用系统朗读控件 TextReader（自带悬浮播控面板），页面内不再自绘悬浮按钮
    Column() {
      BackHeader({
        title: this.kind === 'article' ? '知识点' : '真题详情',
        showAction: true
      }) {
        Text(this.fav ? '★' : '☆')
          .fontSize(FONT.title)
          .fontColor(this.fav ? $r('app.color.favorite') : $r('app.color.text_tertiary'))
          .onClick(() => this.toggleFav())
      }

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
    .padding({ top: this.safeTop, bottom: this.safeBottom })
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

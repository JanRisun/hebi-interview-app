import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Article, Question, Section } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { UserTagStore } from '../utils/UserTagStore';
import { RecorderBar } from '../utils/RecorderBar';
import { TtsButton } from '../utils/TtsButton';
import { TtsFloatButton } from '../utils/TtsFloatButton';
import { FONT, RADIUS, SPACE } from '../utils/Theme';

// 预设快捷标记（点击切换：未加→添加，已加→移除）
const PRESET_TAGS: string[] = ['已背', '易错', '重点', '常考', '待复习', '难点'];

@Entry
@Component
struct Detail {
  @State itemId: string = '';
  @State kind: string = 'article';
  @State article: Article | null = null;
  @State question: Question | null = null;
  @State showAnswer: boolean = false;   // 真题详情：参考答案默认隐藏，手动展开
  @State fav: boolean = false;
  @State userTags: string[] = [];       // 当前内容的用户自定义标签
  @State customInput: string = '';       // 自定义标签输入框

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>;
    this.itemId = p['id'] as string;
    this.kind = p['kind'] as string;
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then(async () => {
      if (this.kind === 'article') {
        this.article = DataStore.articleById(this.itemId) ?? null;
      } else {
        this.question = DataStore.questionById(this.itemId) ?? null;
        this.showAnswer = false;
      }
      this.fav = await FavStore.has(this.itemId);
      this.userTags = await UserTagStore.getUserTags(this.itemId);
    });
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

  // 我的标记管理区：当前标签(点按移除) + 预设快捷 + 自定义输入
  @Builder userTagSection() {
    Column() {
      Text('我的标记')
        .fontSize(FONT.body)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: SPACE.xs })

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
          Text(p)
            .fontSize(FONT.caption)
            .fontColor(this.userTags.includes(p) ? $r('app.color.on_primary') : $r('app.color.brand'))
            .backgroundColor(this.userTags.includes(p) ? $r('app.color.brand') : $r('app.color.tag_bg'))
            .borderRadius(RADIUS.sm)
            .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
            .margin({ top: SPACE.xs, right: SPACE.xs })
            .onClick(() => this.togglePreset(p))
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
    .alignItems(HorizontalAlign.Start)
  }

  @Builder articleView() {
    Scroll() {
      Column() {
        Text(this.article!.title)
          .fontSize(FONT.display)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .margin({ bottom: SPACE.sm })
        Text(this.article!.category)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
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
        // 用 Row 包裹：Column 中子项默认被拉伸成满宽，会变成左侧孤字、右侧大片空白的「空条」，
        // 包一层 Row（默认按内容宽度自适应）即可让按钮收缩为紧凑药丸。
        Row() {
          TtsButton({
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
              Text(s.heading)
                .fontSize(FONT.title)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.brand'))
                .margin({ top: SPACE.md, bottom: SPACE.xs })
            }
            Text(s.body)
              .fontSize(FONT.bodySm)
              .fontColor($r('app.color.text_body'))
              .lineHeight(22)
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
        Text(this.question!.title)
          .fontSize(FONT.display)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .margin({ bottom: SPACE.sm })
        Row() {
          Text(this.question!.type)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.tag_bg'))
            .borderRadius(RADIUS.sm)
            .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
          Text(this.question!.source)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
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
          TtsButton({ text: this.question!.prompt, label: '朗读题目' })
        }
        .margin({ bottom: SPACE.md })
        // 我的标记（用户自定义标签，持久化）
        this.userTagSection()
        Text('【题目】')
          .fontSize(FONT.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand'))
          .margin({ bottom: SPACE.xs })
        Text(this.question!.prompt)
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.text_body'))
          .lineHeight(22)
          .margin({ bottom: SPACE.md })
        // 开口自测：录音 + 回放 + 计时（按当前题 id 存本机）
        RecorderBar({ qid: this.itemId })
        if (this.showAnswer) {
          Row() {
            Text('【参考答案 · 逐字稿】')
              .fontSize(FONT.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand'))
              .layoutWeight(1)   // 空间不足时标题收缩，把位置让给右侧朗读按钮
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            TtsButton({ text: this.question!.answerScript, label: '朗读解析' })
              .margin({ left: SPACE.md })
              .flexShrink(0)   // 不被压缩，保证按钮始终有完整宽度显示文字
          }
          .margin({ bottom: SPACE.xs })
          Text(this.question!.answerScript)
            .fontSize(FONT.bodySm)
            .fontColor($r('app.color.text_body'))
            .lineHeight(22)
        } else {
          Button('查看参考答案（逐字稿）')
            .onClick(() => { this.showAnswer = true; })
            .backgroundColor($r('app.color.brand'))
            .margin({ top: SPACE.xs, bottom: SPACE.xs })
          Text('🔒 先自测口述，再对照参考答案')
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

  build() {
    // Stack 用 BottomStart 对齐：悬浮按钮默认贴左下角，translate 做微调偏移
    Stack({ alignContent: Alignment.BottomStart }) {
      // 底层：页面内容
      Column() {
        Row() {
          Text('‹ 返回')
            .fontSize(FONT.body)
            .fontColor($r('app.color.brand'))
            .onClick(() => router.back())
          Text(this.fav ? '★ 已收藏' : '☆ 收藏')
            .fontSize(FONT.bodySm)
            .fontColor(this.fav ? $r('app.color.favorite') : $r('app.color.text_secondary'))
            .onClick(() => this.toggleFav())
        }
        .width('92%')
        .margin({ top: SPACE.md, bottom: SPACE.sm })
        .justifyContent(FlexAlign.SpaceBetween)

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

      // 上层：TTS 悬浮播控按钮（全局覆盖）
      TtsFloatButton()
    }
    .width('100%')
    .height('100%')
  }
}

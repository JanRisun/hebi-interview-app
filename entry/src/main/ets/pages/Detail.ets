import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Article, Question, Section } from '../model/Types';
import { FavStore } from '../utils/FavStore';
import { FONT, RADIUS, SPACE } from '../utils/Theme';

@Entry
@Component
struct Detail {
  @State itemId: string = '';
  @State kind: string = 'article';
  @State article: Article | null = null;
  @State question: Question | null = null;
  @State showAnswer: boolean = false;   // 真题详情：参考答案默认隐藏，手动展开
  @State fav: boolean = false;

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
    });
  }

  private async toggleFav(): Promise<void> {
    this.fav = await FavStore.toggle(this.itemId);
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
          .margin({ bottom: SPACE.md })
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
        }.margin({ bottom: SPACE.md })
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
        if (this.showAnswer) {
          Text('【参考答案 · 逐字稿】')
            .fontSize(FONT.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
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
  }
}

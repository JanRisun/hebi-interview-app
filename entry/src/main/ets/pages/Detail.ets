import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { Article, Question, Section } from '../model/Types';
import { FavStore } from '../utils/FavStore';

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
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14385c')
          .margin({ bottom: 6 })
        Text(this.article!.category)
          .fontSize(12)
          .fontColor('#888')
          .margin({ bottom: 12 })
        ForEach(this.article!.sections, (s: Section) => {
          Column() {
            if (s.heading) {
              Text(s.heading)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#185FA5')
                .margin({ top: 14, bottom: 4 })
            }
            Text(s.body)
              .fontSize(14)
              .fontColor('#2c2c2a')
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
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14385c')
          .margin({ bottom: 6 })
        Row() {
          Text(this.question!.type)
            .fontSize(12)
            .fontColor('#185FA5')
            .backgroundColor('#E6F1FB')
            .borderRadius(8)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          Text(this.question!.source)
            .fontSize(12)
            .fontColor('#888')
            .margin({ left: 8 })
        }.margin({ bottom: 12 })
        Text('【题目】')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#185FA5')
          .margin({ bottom: 4 })
        Text(this.question!.prompt)
          .fontSize(14)
          .fontColor('#2c2c2a')
          .lineHeight(22)
          .margin({ bottom: 14 })
        if (this.showAnswer) {
          Text('【参考答案 · 逐字稿】')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#185FA5')
            .margin({ bottom: 4 })
          Text(this.question!.answerScript)
            .fontSize(14)
            .fontColor('#2c2c2a')
            .lineHeight(22)
        } else {
          Button('查看参考答案（逐字稿）')
            .onClick(() => { this.showAnswer = true; })
            .backgroundColor('#185FA5')
            .margin({ top: 6, bottom: 6 })
          Text('🔒 先自测口述，再对照参考答案')
            .fontSize(13)
            .fontColor('#888')
            .margin({ top: 4 })
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
          .fontSize(15)
          .fontColor('#185FA5')
          .onClick(() => router.back())
        Text(this.fav ? '★ 已收藏' : '☆ 收藏')
          .fontSize(14)
          .fontColor(this.fav ? '#E0A458' : '#888')
          .onClick(() => this.toggleFav())
      }
      .width('92%')
      .margin({ top: 10, bottom: 8 })
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.article) {
        this.articleView()
      } else if (this.question) {
        this.questionView()
      } else {
        Text('加载中…')
          .fontSize(14)
          .fontColor('#888')
          .margin(40)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

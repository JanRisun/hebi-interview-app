// 素材 Tab：对应原「分类浏览」内容（知识点 / 真题库），顶部搜索框 → 全文检索
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';

@Component
export struct CategoryView {
  @State data: AppData | null = null;
  @State tab: string = 'articles';
  @State kw: string = '';   // 顶部搜索框内容

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then((d) => {
      this.data = d;
    });
  }

  // 顶部搜索 → 全文检索页
  private onSearch(): void {
    if (this.kw.trim()) {
      router.pushUrl({ url: 'pages/Search', params: { 'q': this.kw } });
    }
  }

  @Builder groupHeader(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor('#14385c')
      .backgroundColor('#F5F7FA')
      .width('100%')
      .padding({ top: 10, bottom: 6 })
  }

  @Builder rowItem(title: string, sub: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor('#1f2d3d')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(sub)
          .fontSize(12)
          .fontColor('#888')
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(20)
        .fontColor('#CCC')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .margin({ bottom: 8 })
  }

  @Builder articleList() {
    List() {
      ForEach(this.data!.tags.categories, (cat: string) => {
        ListItemGroup({ header: this.groupHeader(cat) }) {
          ForEach(this.data!.articles.filter((a) => a.category === cat), (a: Article) => {
            ListItem() {
              this.rowItem(a.title, '知识点')
            }
            .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: a.id, kind: 'article' } }))
          }, (a: Article) => a.id)
        }
      }, (cat: string) => cat)
    }
    .width('92%')
    .margin({ top: 8 })
  }

  @Builder questionList() {
    List() {
      ForEach(this.data!.questions, (q: Question) => {
        ListItem() {
          this.rowItem(q.title, q.source)
        }
        .onClick(() => router.pushUrl({ url: 'pages/Detail', params: { id: q.id, kind: 'question' } }))
      }, (q: Question) => q.id)
    }
    .width('92%')
    .margin({ top: 8 })
  }

  build() {
    Column() {
      // 顶部搜索框（对应全文检索功能）
      Row() {
        TextInput({ placeholder: '搜索知识点 / 真题，进入全文检索', text: this.kw })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .padding({ left: 14 })
          .onChange((v: string) => {
            this.kw = v;
          })
          .onSubmit(() => this.onSearch())
        if (this.kw.trim()) {
          Text('搜索')
            .fontSize(14)
            .fontColor('#185FA5')
            .padding({ left: 10, right: 2 })
            .onClick(() => this.onSearch())
        }
      }
      .width('92%')
      .margin({ top: 14, bottom: 8 })

      if (this.data) {
        Tabs({ index: this.tab === 'questions' ? 1 : 0, barPosition: BarPosition.Start }) {
          TabContent() {
            this.articleList()
          }.tabBar('知识点')

          TabContent() {
            this.questionList()
          }.tabBar('真题库')
        }
        .width('100%')
        .layoutWeight(1)
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

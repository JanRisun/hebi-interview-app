// 底部 4 Tab 主框架：素材 / 速记卡 / 真题模考 / 个人中心
import { SymbolGlyph, Resource } from '@kit.ArkUI';
import { CategoryView } from './Category';
import { FlashcardView } from './Flashcard';
import { PracticeView } from './Practice';
import { ProfileView } from './Profile';

@Entry
@Component
struct Index {
  @State current: number = 0;

  // 自定义底部 Tab 按钮（系统 SymbolGlyph 图标 + 文字，选中高亮品牌色）
  @Builder tabBarItem(idx: number, icon: Resource, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary')])
      Text(label)
        .fontSize(11)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          CategoryView()
        }.tabBar(this.tabBarItem(0, $r('sys.symbol.book'), '素材'))

        TabContent() {
          FlashcardView()
        }.tabBar(this.tabBarItem(1, $r('sys.symbol.rectangle_stack'), '速记卡'))

        TabContent() {
          PracticeView()
        }.tabBar(this.tabBarItem(2, $r('sys.symbol.edit'), '真题模考'))

        TabContent() {
          ProfileView()
        }.tabBar(this.tabBarItem(3, $r('sys.symbol.person'), '个人中心'))
      }
      .barPosition(BarPosition.End)
      .onChange((idx: number) => {
        this.current = idx;
      })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

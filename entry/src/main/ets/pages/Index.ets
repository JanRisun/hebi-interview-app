// 底部 4 Tab 主框架：素材 / 速记卡 / 真题模考 / 个人中心
// 外层 Stack：底层 Tabs + 上层 TTS 悬浮播控按钮（全局覆盖）
// SymbolGlyph 是 ArkUI 内置组件（同 Text/Image/Column），无需从 kit 导入
import { CategoryView } from './Category';
import { FlashcardView } from './Flashcard';
import { PracticeView } from './Practice';
import { ProfileView } from './Profile';
import { TtsFloatButton } from './utils/TtsFloatButton';
import { FONT, SPACE } from '../utils/Theme';

@Entry
@Component
struct Index {
  @State current: number = 0;

  // 自定义底部 Tab 按钮（SymbolGlyph 系统符号 + 文字，选中高亮品牌色）
  // iconStr: sys.symbol 资源名（如 'sys.symbol.book'），内部通过 $r() 引用
  @Builder tabBarItem(idx: number, iconStr: string, label: string) {
    Column() {
      SymbolGlyph($r(iconStr))
        .fontSize(24)
        .fontColor(this.current === idx
          ? [$r('app.color.brand'), $r('app.color.brand'), $r('app.color.brand')]
          : [$r('app.color.text_tertiary'), $r('app.color.text_tertiary'), $r('app.color.text_tertiary')])
      Text(label)
        .fontSize(FONT.mini)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .margin({ top: SPACE.xs })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // ====== 底层：Tab 页面内容 ======
      Column() {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() {
            CategoryView()
          }.tabBar(this.tabBarItem(0, 'sys.symbol.book', '素材'))

          TabContent() {
            FlashcardView()
          }.tabBar(this.tabBarItem(1, 'sys.symbol.bookmark', '速记卡'))

          TabContent() {
            PracticeView()
          }.tabBar(this.tabBarItem(2, 'sys.symbol.checkmark_circle', '真题模考'))

          TabContent() {
            ProfileView()
          }.tabBar(this.tabBarItem(3, 'sys.symbol.person', '个人中心'))
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

      // ====== 上层：TTS 悬浮播控按钮（全局覆盖，可拖拽）======
      TtsFloatButton()
        .position({ x: 0, y: 0 }) // 内部自行管理绝对定位
    }
    .width('100%')
    .height('100%')
    .clip(false) // 允许悬浮按钮溢出边界拖拽
  }
}

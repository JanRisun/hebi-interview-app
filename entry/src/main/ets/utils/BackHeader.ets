// 通用子页头部：左侧返回按钮 + 标题 + 右侧可放操作（@BuilderParam action）
// 用法：<BackHeader title={'备考计划'} action: () => { ... } />
import { FONT, SPACE } from './Theme';

@Component
export struct BackHeader {
  @Prop title: string = '';
  @BuilderParam action: () => void = this.emptyAction;
  @Consume pageStack: NavPathStack;

  @Builder
  emptyAction() {
  }

  build() {
    Row() {
      // 返回按钮：点击调用 pageStack.pop() 回到上一页（个人中心 Tab）
      Row() {
        Text('‹')
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('返回')
          .fontSize(FONT.body)
          .fontColor($r('app.color.brand'))
      }
      .align(Alignment.Center)
      .padding({ right: SPACE.md })
      .onClick(() => {
        this.pageStack.pop();
      })

      // 标题：左对齐、占据剩余宽度
      Text(this.title)
        .fontSize(FONT.display)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      // 右侧操作区（默认空）
      this.action()
    }
    .width('92%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: SPACE.lg, bottom: SPACE.md })
  }
}

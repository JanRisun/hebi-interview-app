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
      // 返回按钮：系统箭头符号 + 返回文字，点击 pop 回上一页
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.brand'), $r('app.color.brand'), $r('app.color.brand')])
        Text('返回')
          .fontSize(FONT.body)
          .fontColor($r('app.color.brand'))
          .margin({ left: SPACE.xs })
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
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 右侧操作区（默认空）
      this.action()
    }
    .width('92%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: SPACE.lg, bottom: SPACE.md })
  }
}

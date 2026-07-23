// 通用子页头部（HMOS 代码工坊风格 · 浅色背景子页）
// 视觉规范：左侧 40vp 圆形浅灰底返回按钮 + 左对齐标题 + 右侧 40vp 圆形浅灰底操作按钮（可选）
// 状态栏颜色由 Index.ets 路由 onAppear 统一管理（applyStatusBar('theme')），此处不重复设置。
//
// 用法：
//   1) 仅标题（默认无操作，右侧留 40vp 占位以保持视觉对称）：
//        <BackHeader title={'备考计划'} />
//   2) 带右侧操作（showAction: true，action 槽内容居中显示在 40vp 圆内）：
//        <BackHeader({ title: '详情', showAction: true }) {
//          Text('★').fontSize(18).fontColor($r('app.color.favorite'))
//        }
import { FONT, SPACE } from './Theme';

// 圆形按钮尺寸：与项目内输入框（40vp）保持一致，符合最小触摸目标（>= 40vp）
const BTN_SIZE: number = 40;

@Component
export struct BackHeader {
  @Prop title: string = '';
  // 是否渲染右侧操作按钮；不传则渲染同尺寸占位，保持左右视觉对称
  @Prop showAction: boolean = false;
  @BuilderParam action: () => void = this.emptyAction;
  @Consume pageStack: NavPathStack;

  @Builder
  emptyAction() {
  }

  build() {
    Row() {
      // 左侧：返回按钮 —— 40vp 圆形，浅灰底 + 左箭头系统符号
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary'), $r('app.color.text_primary'), $r('app.color.text_primary')])
      }
      .width(BTN_SIZE)
      .height(BTN_SIZE)
      .borderRadius(BTN_SIZE / 2)
      .backgroundColor($r('app.color.surface_variant'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.pageStack.pop();
      })

      // 中部：标题 —— 左对齐，紧贴返回按钮，占据中间剩余空间
      Text(this.title)
        .fontSize(FONT.title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: SPACE.md })

      // 右侧：操作按钮（可选）—— 与返回按钮同尺寸同底色，action 槽内容居中显示
      if (this.showAction) {
        Row() {
          this.action()
        }
        .width(BTN_SIZE)
        .height(BTN_SIZE)
        .borderRadius(BTN_SIZE / 2)
        .backgroundColor($r('app.color.surface_variant'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      } else {
        // 无操作时填充同尺寸空白占位，保证标题不会因右侧缺位而偏移
        Row()
          .width(BTN_SIZE)
          .height(BTN_SIZE)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.xs, bottom: SPACE.xs })
  }
}

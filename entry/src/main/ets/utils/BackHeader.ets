// 通用子页头部：左侧返回按钮 + 标题
// 用法：在子页 build() 顶部放 <BackHeader title={'我的收藏'} />
import { router } from '@kit.ArkUI';
import { FONT, SPACE } from './Theme';

@Component
export struct BackHeader {
  @Prop title: string = '';

  build() {
    Row() {
      // 返回按钮：点击调用 router.back() 回到上一页（个人中心 Tab）
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
        router.back();
      })

      // 标题：左对齐、占据剩余宽度
      Text(this.title)
        .fontSize(FONT.display)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('92%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: SPACE.lg, bottom: SPACE.md })
  }
}

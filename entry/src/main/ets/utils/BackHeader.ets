// 通用子页头部：左侧返回按钮 + 标题
// 用法：在子页 build() 顶部放 <BackHeader title={'我的收藏'} />
import { router } from '@kit.ArkUI';

@Component
export struct BackHeader {
  @Prop title: string = '';

  build() {
    Row() {
      // 返回按钮：点击调用 router.back() 回到上一页（个人中心 Tab）
      Row() {
        Text('‹')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14385c')
        Text('返回')
          .fontSize(15)
          .fontColor('#14385c')
      }
      .align(Alignment.Center)
      .padding({ right: 12 })
      .onClick(() => {
        router.back();
      })

      // 标题：左对齐、占据剩余宽度
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14385c')
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('92%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 16, bottom: 12 })
  }
}

// 底部 4 Tab 主框架：素材 / 速记卡 / 真题模考 / 个人中心
// 根容器用 Stack 包裹 4 Tab 内容；语音悬浮播控按钮不放在主框架（列表页默认不显示），
// 由各具体页面（详情页 / 速记卡页）按需自行叠加。
// SymbolGlyph 是 ArkUI 内置组件（同 Text/Image/Column），无需从 kit 导入
import { CategoryView } from './Category';
import { FlashcardView } from './Flashcard';
import { PracticeView } from './Practice';
import { ProfileView } from './Profile';
import { Detail } from './Detail';
import { SearchPage } from './Search';
import { Favorites } from './Favorites';
import { StudyRecord } from './StudyRecord';
import { ExamRecord } from './ExamRecord';
import { StudyPlan } from './StudyPlan';
import { FONT, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

@Entry
@Component
struct Index {
  @State current: number = 0;
  @Provide pageStack: NavPathStack = new NavPathStack();

  // 通知/深链启动：若来自今日提醒(target=today)，自动直达备考计划页
  aboutToAppear(): void {
    const target: string = AppStorage.get<string>('launchTarget') ?? '';
    if (target === 'today') {
      AppStorage.set('launchTarget', '');
      this.pageStack.pushPathByName('StudyPlan', {} as Record<string, Object>);
    }
  }

  // 自定义底部 Tab 按钮（SymbolGlyph 系统符号 + 文字 + 选中指示器）
  @Builder tabBarItem(idx: number, icon: Resource, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(this.current === idx ? 24 : 22)
        .fontColor(this.current === idx
          ? [$r('app.color.brand'), $r('app.color.brand'), $r('app.color.brand')]
          : [$r('app.color.text_tertiary'), $r('app.color.text_tertiary'), $r('app.color.text_tertiary')])
      Text(label)
        .fontSize(FONT.mini)
        .fontWeight(this.current === idx ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .margin({ top: SPACE.xs })
      // 选中指示器：选中时显示品牌色小条
      Row()
        .width(20)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.current === idx ? $r('app.color.brand') : $r('app.color.transparent'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height(56)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.surface'))
    }
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  // 路由表：routeName -> NavDestination 组件（参数经 routeMap 的 param 透传）
  @Builder
  private routeMap(name: string, param: Object) {
    if (name === 'Detail') {
      NavDestination() {
        Detail({ params: param })
      }.hideTitleBar(true)
    } else if (name === 'Search') {
      NavDestination() {
        SearchPage({ params: param })
      }.hideTitleBar(true)
    } else if (name === 'Favorites') {
      NavDestination() {
        Favorites()
      }.hideTitleBar(true)
    } else if (name === 'StudyRecord') {
      NavDestination() {
        StudyRecord()
      }.hideTitleBar(true)
    } else if (name === 'ExamRecord') {
      NavDestination() {
        ExamRecord()
      }.hideTitleBar(true)
    } else if (name === 'StudyPlan') {
      NavDestination() {
        StudyPlan()
      }.hideTitleBar(true)
    } else if (name === 'Practice') {
      NavDestination() {
        PracticeView({ params: param })
      }.hideTitleBar(true)
    }
  }

  build() {
    // 根容器：Navigation 路由根 + 4 Tab 内容
    Navigation(this.pageStack) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() {
            CategoryView()
          }.tabBar(this.tabBarItem(0, $r('sys.symbol.book'), '素材'))

          TabContent() {
            FlashcardView()
          }.tabBar(this.tabBarItem(1, $r('sys.symbol.bookmark'), '速记卡'))

          TabContent() {
            PracticeView()
          }.tabBar(this.tabBarItem(2, $r('sys.symbol.checkmark_circle'), '真题模考'))

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
        .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      // 底部保底 24vp：模拟器 / 设备 getWindowAvoidArea 返回 0 时也留出 Tab 栏与手势区间距
      .padding({ top: this.safeTop, bottom: Math.max(this.safeBottom, 24) })
    }
    .width('100%')
    .height('100%')
    }
    .hideTitleBar(true)
    .navDestination(this.routeMap)
    .mode(NavigationMode.Stack)
  }
}

// 预览专用：独立 struct，Previewer 渲染时无需 router/storage 上下文
@Preview
@Component
struct IndexPreview {
  @State current: number = 0;
  @Provide pageStack: NavPathStack = new NavPathStack();

  @Builder tabBarItem(idx: number, icon: Resource, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(this.current === idx ? 24 : 22)
        .fontColor(this.current === idx
          ? [$r('app.color.brand'), $r('app.color.brand'), $r('app.color.brand')]
          : [$r('app.color.text_tertiary'), $r('app.color.text_tertiary'), $r('app.color.text_tertiary')])
      Text(label)
        .fontSize(FONT.mini)
        .fontWeight(this.current === idx ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .margin({ top: SPACE.xs })
      Row()
        .width(20)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.current === idx ? $r('app.color.brand') : $r('app.color.transparent'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() { CategoryView() }.tabBar(this.tabBarItem(0, $r('sys.symbol.book'), '素材'))
          TabContent() { FlashcardView() }.tabBar(this.tabBarItem(1, $r('sys.symbol.bookmark'), '速记卡'))
          TabContent() { PracticeView() }.tabBar(this.tabBarItem(2, $r('sys.symbol.checkmark_circle'), '真题模考'))
          TabContent() { ProfileView() }.tabBar(this.tabBarItem(3, $r('sys.symbol.person'), '个人中心'))
        }
        .barPosition(BarPosition.End)
        .onChange((idx: number) => { this.current = idx; })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.background'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .width('100%')
    .height('100%')
  }
}

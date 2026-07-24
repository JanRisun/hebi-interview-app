// 底部 4 Tab 主框架：知识库 / 速记卡 / 题库 / 个人中心
// 根容器用 Stack 包裹 4 Tab 内容 + 悬浮自定义底部导航栏；
// 自定义导航栏采用「白底胶囊 + 阴影 + 圆角」HMOS 代码工坊风格，左右各留 4% 外边距。
// Tab 栏悬浮在 Tabs 内容之上，4 个内容页 Scroll 底部应预留约 88vp 空间，
// 避免列表最后一行被 Tab 栏遮挡（各页面自行在 Scroll/Column 上 padding bottom）。
// 语音悬浮播控按钮不放在主框架（列表页默认不显示），
// 由各具体页面（详情页 / 速记卡页）按需自行叠加。
// SymbolGlyph 是 ArkUI 内置组件（同 Text/Image/Column），无需从 kit 导入
import { CategoryView } from './Category';
import { FlashcardView } from './Flashcard';
import { PracticeView } from './Practice';
import { ProfileView } from './Profile';
import { Detail } from './Detail';
import { SearchPage } from './Search';
import { Favorites } from './Favorites';
import { KnowledgeView } from './Knowledge';
import { QuestionBankView } from './QuestionBank';
import { MyMarkView } from './MyMark';
import { StudyRecord } from './StudyRecord';
import { ExamRecord } from './ExamRecord';
import { StudyPlan } from './StudyPlan';
import { FONT, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { applyStatusBar } from '../utils/StatusBar';

// 自定义悬浮底部 Tab 栏固定高度 + 上下间距
// 4 个内容页 Scroll 底部应预留此高度（外加自身 safeBottom）作为底部留白
const TAB_BAR_HEIGHT: number = 56;
const TAB_BAR_TOP_GAP: number = 8;    // Tabs 内容与 Tab 栏顶部之间的间距
const TAB_BAR_BOTTOM_GAP: number = 28; // Tab 栏与屏幕底部的间距（不含安全区，避开手势操作条）

@Entry
@Component
struct Index {
  @State current: number = 0;
  @Provide pageStack: NavPathStack = new NavPathStack();
  // Tabs 控制器：自定义 Tab 栏点击时主动驱动 Tabs 切换
  private tabsController: TabsController = new TabsController();

  // 通知/深链启动：若来自今日提醒(target=today)，自动直达备考计划页
  aboutToAppear(): void {
    // 主页 4 个 Tab 均为品牌渐变头部覆盖状态栏，状态栏图标统一用浅色（白）
    applyStatusBar('brand');
    const target: string = AppStorage.get<string>('launchTarget') ?? '';
    if (target === 'today') {
      AppStorage.set('launchTarget', '');
      // 延迟到首帧渲染完成后再压栈，避免在组件初始渲染期间修改 @Provide pageStack 状态
      // （否则会触发 "State variable 'pageStack' has changed during render!" 告警）。
      setTimeout(() => {
        this.pageStack.pushPathByName('StudyPlan', {} as Record<string, Object>);
      }, 0);
    }
  }

  // 自定义底部 Tab 按钮（HMOS 代码工坊风格：白底胶囊悬浮、图标+文字上下、
  // 选中态品牌蓝、未选中态深色 text_primary）
  @Builder tabBarItem(idx: number, icon: Resource, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary')])
      Text(label)
        .fontSize(FONT.mini)
        .fontWeight(this.current === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary'))
        .margin({ top: SPACE.xs })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.current !== idx) {
        this.current = idx;
        this.tabsController.changeIndex(idx);
      }
    })
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  // 路由表：routeName -> NavDestination 组件（参数经 routeMap 的 param 透传）
  // 子页多为浅色背景（BackHeader），进入时状态栏跟随主题；退出回到品牌主页恢复白字。
  // Practice 路由（开始模考）承载的 PracticeView 自身为品牌渐变头部，仍用白字；题库主 Tab 复用真题库列表页。
  @Builder
  private routeMap(name: string, param: Object) {
    if (name === 'Detail') {
      NavDestination() {
        Detail({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Search') {
      NavDestination() {
        SearchPage({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Favorites') {
      NavDestination() {
        Favorites()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'StudyRecord') {
      NavDestination() {
        StudyRecord()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'ExamRecord') {
      NavDestination() {
        ExamRecord()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'StudyPlan') {
      NavDestination() {
        StudyPlan()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Practice') {
      NavDestination() {
        PracticeView({ params: param })
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('brand');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'Knowledge') {
      NavDestination() {
        KnowledgeView()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'QuestionBank') {
      NavDestination() {
        QuestionBankView()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    } else if (name === 'MyMark') {
      NavDestination() {
        MyMarkView()
      }.hideTitleBar(true)
      .onAppear(() => {
        applyStatusBar('theme');
      })
      .onDisAppear(() => {
        applyStatusBar('brand');
      })
    }
  }

  build() {
    // 根容器：Navigation 路由根 + Stack(Tabs 内容 + 悬浮自定义 Tab 栏)
    Navigation(this.pageStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 4 Tab 内容区（隐藏默认 tabBar，留出空间给下方悬浮 Tab 栏）
        Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
          TabContent() { CategoryView() }.tabBar(this.tabBarItem(0, $r('sys.symbol.book'), '知识库'))
          TabContent() { FlashcardView() }.tabBar(this.tabBarItem(1, $r('sys.symbol.bookmark'), '速记卡'))
          TabContent() { QuestionBankView({ root: true }) }.tabBar(this.tabBarItem(2, $r('sys.symbol.checkmark_circle'), '题库'))
          TabContent() { ProfileView() }.tabBar(this.tabBarItem(3, $r('sys.symbol.person'), '个人中心'))
        }
        .barPosition(BarPosition.End)
        .barHeight(0)
        .onChange((idx: number) => {
          this.current = idx;
        })
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
        .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)

        // 悬浮自定义底部 Tab 栏：白底胶囊 + 圆角 + 阴影，左右各 4% 外边距
        Column() {
          Row() {
            this.tabBarItem(0, $r('sys.symbol.book'), '知识库')
            this.tabBarItem(1, $r('sys.symbol.bookmark'), '速记卡')
            this.tabBarItem(2, $r('sys.symbol.checkmark_circle'), '题库')
            this.tabBarItem(3, $r('sys.symbol.person'), '个人中心')
          }
          .width('92%')
          .height(TAB_BAR_HEIGHT)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(TAB_BAR_HEIGHT / 2)
          .padding({ left: SPACE.xs, right: SPACE.xs })
          .shadow({ radius: 16, color: '#1F2A3722', offsetY: 4 })
        }
        .width('100%')
        .padding({
          top: TAB_BAR_TOP_GAP,
          bottom: this.safeBottom + TAB_BAR_BOTTOM_GAP
        })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
      // 安全区内缩由各 Tab 页面根 Column 的 padding(top/bottom: safeTop/safeBottom) 统一处理，
      // 此处不再叠加，避免顶部双倍空白（之前 safeTop 被叠两次导致"我的"距状态栏过远）。
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
  @StorageProp('safeBottom') safeBottom: number = 24;
  private tabsController: TabsController = new TabsController();

  @Builder tabBarItem(idx: number, icon: Resource, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary')])
      Text(label)
        .fontSize(FONT.mini)
        .fontWeight(this.current === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_primary'))
        .margin({ top: SPACE.xs })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.current !== idx) {
        this.current = idx;
        this.tabsController.changeIndex(idx);
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
        TabContent() { CategoryView() }.tabBar(this.tabBarItem(0, $r('sys.symbol.book'), '知识库'))
        TabContent() { FlashcardView() }.tabBar(this.tabBarItem(1, $r('sys.symbol.bookmark'), '速记卡'))
        TabContent() { QuestionBankView({ root: true }) }.tabBar(this.tabBarItem(2, $r('sys.symbol.checkmark_circle'), '题库'))
        TabContent() { ProfileView() }.tabBar(this.tabBarItem(3, $r('sys.symbol.person'), '个人中心'))
      }
      .barPosition(BarPosition.End)
      .barHeight(0)
      .onChange((idx: number) => { this.current = idx; })
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))

      Column() {
        Row() {
          this.tabBarItem(0, $r('sys.symbol.book'), '知识库')
          this.tabBarItem(1, $r('sys.symbol.bookmark'), '速记卡')
          this.tabBarItem(2, $r('sys.symbol.checkmark_circle'), '题库')
          this.tabBarItem(3, $r('sys.symbol.person'), '个人中心')
        }
        .width('92%')
        .height(TAB_BAR_HEIGHT)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(TAB_BAR_HEIGHT / 2)
        .padding({ left: SPACE.xs, right: SPACE.xs })
        .shadow({ radius: 16, color: '#1F2A3722', offsetY: 4 })
      }
      .width('100%')
      .padding({ top: TAB_BAR_TOP_GAP, bottom: this.safeBottom + TAB_BAR_BOTTOM_GAP })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

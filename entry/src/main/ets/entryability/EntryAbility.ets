import { AbilityConstant, UIAbility, Want, Configuration, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { WindowManager } from '@kit.SpeechKit';
import { DataStore } from '../model/DataStore';
import { FavStore } from '../utils/FavStore';
import { UserTagStore } from '../utils/UserTagStore';
import { ensureReminder } from '../utils/ReminderHelper';
import { registerWindow, applyStatusBar, reapplyStatusBar } from '../utils/StatusBar';

const DOMAIN: number = 0x0000;
const TAG: string = 'InterviewPrep';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 记录通知/深链启动目标（如代理提醒点击带 target=today），供 Index 路由直达
    let launchTarget: string = '';
    if (want.parameters && want.parameters['target']) {
      launchTarget = want.parameters['target'] as string;
    }
    AppStorage.setOrCreate('launchTarget', launchTarget);
    // 记录系统深浅色模式到 AppStorage，供页面在 Token 自动切换之外参考
    AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    // 预加载数据、收藏存储与用户标签存储
    DataStore.load(this.context)
      .then(() => FavStore.init(this.context))
      .then(() => UserTagStore.init(this.context))
      .catch((e: Error) => hilog.error(DOMAIN, TAG, 'init failed: %{public}s', JSON.stringify(e)));
  }

  // 热启动（App 已在后台）从通知/深链点开时走此回调，需同步更新 launchTarget
  onNewWant(want: Want): void {
    let launchTarget: string = '';
    if (want.parameters && want.parameters['target']) {
      launchTarget = want.parameters['target'] as string;
    }
    AppStorage.setOrCreate('launchTarget', launchTarget);
  }

  // App 回到前台（含冷启动后首次进入）兜底：若已开启每日提醒，按已保存时刻重新发布，
  // 防止系统提醒服务重置/应用数据清理后任务丢失，导致不再弹通知。
  onForeground(): void {
    ensureReminder(this.context as common.UIAbilityContext);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统配置（含深浅色）变化时，同步最新 colorMode
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
    // 主题切换后重设状态栏图标色，避免状态栏文字色残留上一模式
    reapplyStatusBar();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 语音朗读控件 TextReader 依赖 WindowStage 承载系统朗读面板，需在加载内容前注册
    WindowManager.setWindowStage(windowStage);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      try {
        const win: window.Window = windowStage.getMainWindowSync();
        // 缓存主窗口，供状态栏图标色管理（utils/StatusBar）调用
        registerWindow(win);
        // 沉浸式：窗口全屏，让页面背景延伸到状态栏 / 底部导航手势区
        // （各页根容器配合 expandSafeArea 将内容避让到安全区内，仅背景延伸）
        win.setWindowLayoutFullScreen(true).catch((e: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(e));
        });
        // 状态栏 / 导航栏图标色：主页为品牌渐变头部，状态栏用浅色（白）图标保证可读；
        // 浅色背景子页跟随系统深浅色。统一由 utils/StatusBar 管理（见 applyStatusBar）。
        applyStatusBar('brand');
        // 计算并缓存安全区 Insets（状态栏高 / 底部导航手势区高，单位 vp）。
        // 全屏沉浸模式下系统不预留安全区，需各页按此值内缩 padding 让内容避让状态栏与底部操作栏。
        const applySafeInsets = (): void => {
          const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          AppStorage.setOrCreate('safeTop', px2vp(area.topRect.height));
          AppStorage.setOrCreate('safeBottom', px2vp(area.bottomRect.height));
        };
        applySafeInsets();
        win.on('avoidAreaChange', (data): void => {
          if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
            AppStorage.setOrCreate('safeTop', px2vp(data.area.topRect.height));
            AppStorage.setOrCreate('safeBottom', px2vp(data.area.bottomRect.height));
          }
        });
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'window setup failed: %{public}s', JSON.stringify(e));
      }
    });
  }
}

import { AbilityConstant, UIAbility, Want, Configuration, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DataStore } from '../model/DataStore';
import { FavStore } from '../utils/FavStore';
import { UserTagStore } from '../utils/UserTagStore';
import { ensureReminder } from '../utils/ReminderHelper';

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
    // 语音播报全局态（多个朗读按钮共享同一 TTS 引擎）
    AppStorage.setOrCreate('ttsPlaying', false);
    AppStorage.setOrCreate('ttsPaused', false);
    AppStorage.setOrCreate('ttsText', '');
    AppStorage.setOrCreate('ttsSpeed', 1.0);
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
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }
}

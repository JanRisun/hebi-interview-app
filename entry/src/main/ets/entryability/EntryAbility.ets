import { AbilityConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DataStore } from '../model/DataStore';
import { FavStore } from '../utils/FavStore';
import { UserTagStore } from '../utils/UserTagStore';

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

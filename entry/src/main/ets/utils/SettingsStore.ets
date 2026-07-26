// 全局设置：外观（主题模式）与文字大小持久化 + 应用。
//  - 主题模式：'system' | 'light' | 'dark'，通过 window.setColorMode 全局即时切换（资源自动重解析）。
//  - 文字大小：0=标准 1=大 2=特大，缩放系数写入 AppStorage('fontScale')，FONT getter 实时读取。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { reapplyStatusBar } from './StatusBar';

const PREF: string = 'settings';
const KEY_THEME: string = 'theme_mode';   // 'system' | 'light' | 'dark'
const KEY_FONT: string = 'font_level';    // 0 | 1 | 2

export type ThemeMode = 'system' | 'light' | 'dark';

// 字号档位缩放系数（对应 标准 / 大 / 特大）
export const FONT_LEVELS: number[] = [1.0, 1.15, 1.3];
export const FONT_LEVEL_LABELS: string[] = ['标准', '大', '特大'];

// 读取持久化设置并同步到 AppStorage（在 EntryAbility 早期调用，早于各页面构建）
export function initSettings(ctx: common.UIAbilityContext): void {
  preferences.getPreferences(ctx, PREF).then((p) => {
    const theme: string = (p.getSync(KEY_THEME, 'system') as string);
    const fontLevel: number = (p.getSync(KEY_FONT, 0) as number);
    AppStorage.setOrCreate('themeMode', theme);
    AppStorage.setOrCreate('fontScale', FONT_LEVELS[fontLevel] ?? 1.0);
  });
}

// 窗口就绪后应用主题（setColorMode 需主窗口）
export function applyTheme(ctx: common.UIAbilityContext): void {
  const mode: string = (AppStorage.get('themeMode') as string) ?? 'system';
  setWindowColorMode(ctx, mode as ThemeMode);
}

function setWindowColorMode(ctx: common.UIAbilityContext, mode: ThemeMode): void {
  window.getLastWindow(ctx).then((win: window.Window) => {
    let cm: window.ColorMode;
    if (mode === 'light') cm = window.ColorMode.MODE_LIGHT;
    else if (mode === 'dark') cm = window.ColorMode.MODE_DARK;
    else cm = window.ColorMode.MODE_AUTO;
    try {
      win.setColorMode(cm);
    } catch (e) {
      // 部分设备/模拟器窗口能力受限，忽略即可
    }
    // 同步状态栏判定用的 currentColorMode，保证状态栏前景色与强制主题一致
    if (mode === 'system') {
      AppStorage.set('currentColorMode', ctx.config.colorMode);
    } else {
      AppStorage.set('currentColorMode',
        mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    }
    reapplyStatusBar();
  }).catch(() => {
    // 窗口未就绪，忽略
  });
}

export function setThemeMode(ctx: common.UIAbilityContext, mode: ThemeMode): void {
  AppStorage.set('themeMode', mode);
  setWindowColorMode(ctx, mode);
  preferences.getPreferences(ctx, PREF).then((p) => {
    p.putSync(KEY_THEME, mode);
    p.flush();
  });
}

export function setFontLevel(ctx: common.UIAbilityContext, level: number): void {
  const lv: number = Math.max(0, Math.min(FONT_LEVELS.length - 1, level));
  const scale: number = FONT_LEVELS[lv] ?? 1.0;
  AppStorage.set('fontScale', scale);
  preferences.getPreferences(ctx, PREF).then((p) => {
    p.putSync(KEY_FONT, lv);
    p.flush();
  });
}

export function getThemeMode(ctx: common.UIAbilityContext): Promise<ThemeMode> {
  return preferences.getPreferences(ctx, PREF)
    .then((p): ThemeMode => (p.getSync(KEY_THEME, 'system') as ThemeMode));
}

export function getFontLevel(ctx: common.UIAbilityContext): Promise<number> {
  return preferences.getPreferences(ctx, PREF)
    .then((p): number => (p.getSync(KEY_FONT, 0) as number));
}

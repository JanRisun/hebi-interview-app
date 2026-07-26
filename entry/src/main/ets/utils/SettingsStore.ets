// 全局设置：外观（主题模式）与文字大小持久化 + 应用。
//  - 主题模式：'system' | 'light' | 'dark'，通过 ApplicationContext.setColorMode 全局即时切换（资源自动重解析）。
//  - 文字大小：0=标准 1=大 2=特大，缩放系数写入 AppStorage('fontScale')，FONT getter 实时读取。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
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

// 窗口就绪后应用主题（NEXT 通过 ApplicationContext.setColorMode 全局即时切换，资源自动重解析）
export function applyTheme(ctx: common.UIAbilityContext): void {
  const mode: string = (AppStorage.get('themeMode') as string) ?? 'system';
  setAppColorMode(ctx, mode as ThemeMode);
}

// 应用级颜色模式：'system' 跟随系统，'light' / 'dark' 强制。
// NEXT 已弃用 window.Window.setColorMode，统一改用 ApplicationContext.setColorMode。
function setAppColorMode(ctx: common.UIAbilityContext, mode: ThemeMode): void {
  let cm: ConfigurationConstant.ColorMode;
  if (mode === 'light') {
    cm = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  } else if (mode === 'dark') {
    cm = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  } else {
    cm = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
  try {
    const appCtx: common.ApplicationContext = ctx.getApplicationContext();
    appCtx.setColorMode(cm);
  } catch (e) {
    // 部分环境不支持应用级 setColorMode，忽略即可
  }
  // 同步状态栏判定用的 currentColorMode，保证状态栏前景色与强制主题一致
  if (mode === 'system') {
    AppStorage.set('currentColorMode', ctx.config.colorMode);
  } else {
    AppStorage.set('currentColorMode',
      mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  }
  reapplyStatusBar();
}

export function setThemeMode(ctx: common.UIAbilityContext, mode: ThemeMode): void {
  AppStorage.set('themeMode', mode);
  setAppColorMode(ctx, mode);
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
  // FONT getter 通过 AppStorage.get('fontScale') 读取，属于非响应式取值，
  // 仅改字号无法可靠触发已挂载组件重渲染。这里复用“切换外观”的已验证机制：
  // 重新应用一次主题（强制产生一次颜色模式切换事件），使系统重解析资源、
  // 全局组件重渲染，从而在 build 中重新读取 FONT，字号即时全站生效。
  const cur: ThemeMode = (AppStorage.get('themeMode') as ThemeMode) ?? 'system';
  if (cur === 'system') {
    setAppColorMode(ctx, 'light');
    setAppColorMode(ctx, 'system');
  } else {
    setAppColorMode(ctx, 'system');
    setAppColorMode(ctx, cur);
  }
}

export function getThemeMode(ctx: common.UIAbilityContext): Promise<ThemeMode> {
  return preferences.getPreferences(ctx, PREF)
    .then((p): ThemeMode => (p.getSync(KEY_THEME, 'system') as ThemeMode));
}

export function getFontLevel(ctx: common.UIAbilityContext): Promise<number> {
  return preferences.getPreferences(ctx, PREF)
    .then((p): number => (p.getSync(KEY_FONT, 0) as number));
}

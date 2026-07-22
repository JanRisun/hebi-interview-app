/**
 * StatusBar.ets
 * 状态栏 / 导航栏图标色统一管理（替代 EntryAbility 中一次性的 setWindowSystemBarProperties）。
 * - 'brand'：页面为品牌渐变头部（PageHero）覆盖状态栏，状态栏用浅色（白）图标保证可读。
 * - 'theme'：浅色背景子页，状态栏图标跟随系统深浅色。
 * 导航栏图标色始终跟随主题（底部 Tab 栏底色随主题变化）。
 */
import { window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

let mainWindow: window.Window | null = null;
let currentMode: 'brand' | 'theme' = 'brand';

/**
 * 缓存主窗口，供后续设置状态栏图标色使用。
 */
export function registerWindow(win: window.Window): void {
  mainWindow = win;
}

/**
 * 按策略设置状态栏 / 导航栏图标色。
 * @param mode 'brand' 品牌头用白字；'theme' 跟随系统深浅色。
 */
export function applyStatusBar(mode: 'brand' | 'theme'): void {
  currentMode = mode;
  if (!mainWindow) {
    return;
  }
  const isDark: boolean = AppStorage.get<number>('currentColorMode') ===
    ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  const statusColor: string = (mode === 'brand') ? '#FFFFFF' : (isDark ? '#FFFFFF' : '#000000');
  const navColor: string = isDark ? '#FFFFFF' : '#000000';
  mainWindow.setWindowSystemBarProperties({
    statusBarContentColor: statusColor,
    navigationBarContentColor: navColor
  }).catch((e: BusinessError): void => {
    console.error('StatusBar applyStatusBar failed: ' + JSON.stringify(e));
  });
}

/**
 * 主题切换时按当前策略重设状态栏图标色，避免残留旧模式。
 */
export function reapplyStatusBar(): void {
  applyStatusBar(currentMode);
}

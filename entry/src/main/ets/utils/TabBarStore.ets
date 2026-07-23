// 底部 Tab 栏配置持久化：顺序 + 显隐 + 名称
// 默认四项（知识库 / 速记卡 / 题库 / 个人中心），用户可在「首页标签栏管理」中编辑排序与显隐。
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export interface TabItem {
  key: string;     // 'material' | 'flashcard' | 'practice' | 'profile'
  label: string;   // 显示名称（可编辑）
  visible: boolean; // 是否在底部栏显示
}

const PREF_NAME: string = 'app_prefs';
const KEY: string = 'tabbar_config';

export class TabBarStore {
  // 默认 Tab 配置（与 Index 主框架一致）
  static defaultTabs(): TabItem[] {
    return [
      { key: 'material', label: '知识库', visible: true },
      { key: 'flashcard', label: '速记卡', visible: true },
      { key: 'practice', label: '题库', visible: true },
      { key: 'profile', label: '个人中心', visible: true }
    ];
  }

  // 图标按 key 解析为资源字面量（避免 $r(变量) 的编译期校验问题）
  static icon(key: string): Resource {
    switch (key) {
      case 'material':
        return $r('sys.symbol.book');
      case 'flashcard':
        return $r('sys.symbol.bookmark');
      case 'practice':
        return $r('sys.symbol.checkmark_circle');
      case 'profile':
        return $r('sys.symbol.person');
      default:
        return $r('sys.symbol.book');
    }
  }

  // 读取配置：优先持久化值，缺项/损坏时回退默认；至少保留一项可见
  static async load(ctx: common.UIAbilityContext): Promise<TabItem[]> {
    try {
      const pf: preferences.Preferences = await preferences.getPreferences(ctx, PREF_NAME);
      const raw: string = (await pf.get(KEY, '')) as string;
      if (raw) {
        const arr: TabItem[] = JSON.parse(raw) as TabItem[];
        if (arr && arr.length > 0) {
          const defs: TabItem[] = TabBarStore.defaultTabs();
          const map: Map<string, TabItem> = new Map(arr.map((t: TabItem) => [t.key, t]));
          const merged: TabItem[] = defs.map((d: TabItem) => map.get(d.key) ?? { key: d.key, label: d.label, visible: d.visible });
          // 兼容旧版持久化：把「真题模考」默认标签改名为「题库」
          merged.forEach((t: TabItem) => {
            if (t.key === 'practice' && t.label === '真题模考') {
              t.label = '题库';
            }
          });
          if (!merged.some((t: TabItem) => t.visible)) {
            merged[0].visible = true;
          }
          return merged;
        }
      }
    } catch (e) {
      // 解析失败回退默认
    }
    return TabBarStore.defaultTabs();
  }

  // 保存配置到 Preferences
  static async save(ctx: common.UIAbilityContext, tabs: TabItem[]): Promise<void> {
    const pf: preferences.Preferences = await preferences.getPreferences(ctx, PREF_NAME);
    await pf.put(KEY, JSON.stringify(tabs));
    await pf.flush();
  }
}

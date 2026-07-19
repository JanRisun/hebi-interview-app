import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const KEY: string = 'fav_ids';

// 收藏存储：基于 Preferences 持久化收藏 id 列表
export class FavStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (!FavStore.store) {
      FavStore.store = await preferences.getPreferences(context, 'interview_pref');
    }
  }

  static async getIds(): Promise<string[]> {
    if (!FavStore.store) {
      return [];
    }
    const v: string = (await FavStore.store.get(KEY, '[]')) as string;
    try {
      return JSON.parse(v) as string[];
    } catch (e) {
      return [];
    }
  }

  static async has(id: string): Promise<boolean> {
    const ids: string[] = await FavStore.getIds();
    return ids.includes(id);
  }

  // 切换收藏状态，返回切换后的"是否已收藏"
  static async toggle(id: string): Promise<boolean> {
    const ids: string[] = await FavStore.getIds();
    const i: number = ids.indexOf(id);
    let now: boolean;
    if (i >= 0) {
      ids.splice(i, 1);
      now = false;
    } else {
      ids.push(id);
      now = true;
    }
    await FavStore.store!.put(KEY, JSON.stringify(ids));
    await FavStore.store!.flush();
    return now;
  }
}

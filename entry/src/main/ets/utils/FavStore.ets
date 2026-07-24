import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const KEY: string = 'fav_ids';

// 收藏存储：基于 Preferences 持久化收藏 id 列表
export class FavStore {
  private static store: preferences.Preferences | null = null;
  // 缓存 Ability 上下文，便于 store 未就绪时按需（重新）建立，避免空指针崩溃
  private static ctx: common.UIAbilityContext | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (context) {
      FavStore.ctx = context;
    }
    await FavStore.ensureStore();
  }

  // 若 store 尚未建立（init 未完成/失败），用已缓存的 context 重新建立；
  // 全程不依赖「!」断言，store 无法获取时优雅降级，调用方不会因此崩溃。
  private static async ensureStore(): Promise<boolean> {
    if (FavStore.store) {
      return true;
    }
    if (!FavStore.ctx) {
      return false;
    }
    try {
      FavStore.store = await preferences.getPreferences(FavStore.ctx, 'interview_pref');
    } catch (e) {
      FavStore.store = null;
      return false;
    }
    return FavStore.store != null;
  }

  static async getIds(): Promise<string[]> {
    if (!(await FavStore.ensureStore())) {
      return [];
    }
    const v: string = (await FavStore.store!.get(KEY, '[]')) as string;
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

  // 同步判断是否已收藏（供展示页 build 使用）
  static hasSync(id: string): boolean {
    return FavStore.getFavIds().includes(id);
  }

  // 切换收藏状态，返回切换后的"是否已收藏"。
  // 即使 store 暂时不可用时也不会抛异常导致 app 崩溃，仅本次切换不落盘。
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
    if (FavStore.store) {
      await FavStore.store.put(KEY, JSON.stringify(ids));
      await FavStore.store.flush();
    }
    FavStore.notifyChange();
    return now;
  }

  // 同步读取全部收藏 id（store 未就绪时返回空数组，不崩溃）
  static getFavIds(): string[] {
    if (!FavStore.store) {
      return [];
    }
    const raw: string = FavStore.store.getSync(KEY, '[]') as string;
    try {
      return JSON.parse(raw) as string[];
    } catch (e) {
      return [];
    }
  }

  // 通知全局：收藏状态已变更，供展示页（收藏列表/个人中心）自动刷新
  static notifyChange(): void {
    const v: number = (AppStorage.get('favTagVersion') as number) ?? 0;
    AppStorage.set('favTagVersion', v + 1);
  }
}

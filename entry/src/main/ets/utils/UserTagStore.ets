import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const KEY: string = 'user_tags_map';

// 预设快捷标记：详情页「我的标记」悬浮按钮与个人中心「我的标记」共用，保证选项完全一致
export const PRESET_MARK_TAGS: string[] = ['常考', '重点', '难点', '易错', '稍后再看', '已掌握'];

// 用户自定义标签存储：基于 Preferences 持久化「内容 id → 标签数组」映射
// 与 FavStore 共用 'interview_pref' 文件，使用独立 key。
// 采用内存缓存 cache 作为唯一数据源，所有读写都基于它，整体持久化，
// 避免每次重新 get/parse 全量 map 在并发/复用下互相覆盖其它 id 的标签。
export class UserTagStore {
  private static store: preferences.Preferences | null = null;
  private static cache: Record<string, string[]> = {};

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (!UserTagStore.store) {
      UserTagStore.store = await preferences.getPreferences(context, 'interview_pref');
    }
    const v: string = (await UserTagStore.store.get(KEY, '{}')) as string;
    try {
      UserTagStore.cache = JSON.parse(v) as Record<string, string[]>;
    } catch (e) {
      UserTagStore.cache = {};
    }
  }

  // 读取某内容的用户标签（返回副本，防止外部持有并修改缓存数组）
  static async getUserTags(id: string): Promise<string[]> {
    const arr: string[] | undefined = UserTagStore.cache[id];
    return arr ? arr.slice() : [];
  }

  // 将内存缓存整体写入 Preferences
  private static async persist(): Promise<void> {
    if (!UserTagStore.store) return;
    await UserTagStore.store.put(KEY, JSON.stringify(UserTagStore.cache));
    await UserTagStore.store.flush();
  }

  // 给某内容添加一个标签（去重），返回最新标签数组副本
  static async addTag(id: string, tag: string): Promise<string[]> {
    const t: string = tag.trim();
    if (!t) return UserTagStore.getUserTags(id);
    if (!UserTagStore.cache[id]) {
      UserTagStore.cache[id] = [];
    }
    const arr: string[] = UserTagStore.cache[id];
    if (!arr.includes(t)) {
      arr.push(t);
      await UserTagStore.persist();
      UserTagStore.notifyChange();
    }
    return arr.slice();
  }

  // 移除某内容的某个标签，返回最新标签数组副本
  static async removeTag(id: string, tag: string): Promise<string[]> {
    const arr: string[] = (UserTagStore.cache[id] ?? []).filter((x: string) => x !== tag);
    UserTagStore.cache[id] = arr;
    await UserTagStore.persist();
    UserTagStore.notifyChange();
    return arr.slice();
  }

  // 被标记的内容数量（即映射中标签非空的内容 id 个数），用于个人中心「我的标记」计数
  static async markCount(): Promise<number> {
    const ids: string[] = Object.keys(UserTagStore.cache);
    return ids.filter((id: string): boolean => (UserTagStore.cache[id]?.length ?? 0) > 0).length;
  }

  // 清空全部用户自定义标签（设置页「清除我的标记」调用），并通知全局刷新
  static async clearAll(): Promise<void> {
    UserTagStore.cache = {};
    await UserTagStore.persist();
    UserTagStore.notifyChange();
  }

  // 全部用户自定义标签（去重、排序），用于筛选条
  static async allTags(): Promise<string[]> {
    const set: Set<string> = new Set<string>();
    Object.values(UserTagStore.cache).forEach((arr: string[]) => arr.forEach((t: string) => set.add(t)));
    return Array.from(set).sort();
  }

  // 完整映射（按需返回副本），供筛选时按内容判断
  static async allMap(): Promise<Record<string, string[]>> {
    const m: Record<string, string[]> = {};
    Object.keys(UserTagStore.cache).forEach((k: string) => { m[k] = UserTagStore.cache[k].slice(); });
    return m;
  }

  // 通知全局：用户标签已变更，供展示页（我的标记/素材筛选/个人中心）自动刷新
  static notifyChange(): void {
    const v: number = (AppStorage.get('favTagVersion') as number) ?? 0;
    AppStorage.set('favTagVersion', v + 1);
  }
}

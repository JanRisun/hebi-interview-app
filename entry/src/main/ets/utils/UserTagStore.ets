import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const KEY: string = 'user_tags_map';

// 用户自定义标签存储：基于 Preferences 持久化「内容 id → 标签数组」映射
// 与 FavStore 共用 'interview_pref' 文件，使用独立 key
export class UserTagStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (!UserTagStore.store) {
      UserTagStore.store = await preferences.getPreferences(context, 'interview_pref');
    }
  }

  // 读取完整映射 { id: string[] }
  private static async map(): Promise<Record<string, string[]>> {
    if (!UserTagStore.store) {
      return {};
    }
    const v: string = (await UserTagStore.store.get(KEY, '{}')) as string;
    try {
      return JSON.parse(v) as Record<string, string[]>;
    } catch (e) {
      return {};
    }
  }

  // 读取某内容的用户标签
  static async getUserTags(id: string): Promise<string[]> {
    const m = await UserTagStore.map();
    return m[id] ?? [];
  }

  // 写入某内容的用户标签（空数组则删除该 id 记录）
  static async save(id: string, tags: string[]): Promise<void> {
    if (!UserTagStore.store) return;
    const m = await UserTagStore.map();
    if (tags.length === 0) {
      m[id] = [];   // ArkTS 禁 delete 操作符，赋空数组等效（getUserTags 对缺失/空均返回 []）
    } else {
      m[id] = tags;
    }
    await UserTagStore.store.put(KEY, JSON.stringify(m));
    await UserTagStore.store.flush();
  }

  // 给某内容添加一个标签（去重），返回最新标签数组
  static async addTag(id: string, tag: string): Promise<string[]> {
    const t: string = tag.trim();
    if (!t) return UserTagStore.getUserTags(id);
    const cur: string[] = await UserTagStore.getUserTags(id);
    if (!cur.includes(t)) {
      cur.push(t);
      await UserTagStore.save(id, cur);
    }
    return cur;
  }

  // 移除某内容的某个标签，返回最新标签数组
  static async removeTag(id: string, tag: string): Promise<string[]> {
    const cur: string[] = await UserTagStore.getUserTags(id);
    const next: string[] = cur.filter((x: string) => x !== tag);
    await UserTagStore.save(id, next);
    return next;
  }

  // 全部用户自定义标签（去重、排序），用于筛选条
  static async allTags(): Promise<string[]> {
    const m = await UserTagStore.map();
    const set: Set<string> = new Set<string>();
    Object.values(m).forEach((arr: string[]) => arr.forEach((t: string) => set.add(t)));
    return Array.from(set).sort();
  }

  // 完整映射，供筛选时按内容判断
  static async allMap(): Promise<Record<string, string[]>> {
    return UserTagStore.map();
  }
}

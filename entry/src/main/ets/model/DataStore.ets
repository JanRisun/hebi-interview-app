import { AppData, Article, Question, MockSet } from './Types';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

// 从 rawfile 加载结构化数据（一次性缓存）
export class DataStore {
  private static _data: AppData | null = null;

  static async load(context: common.UIAbilityContext): Promise<AppData> {
    if (DataStore._data) {
      return DataStore._data;
    }
    const buf: Uint8Array = await context.resourceManager.getRawFileContent('data.json');
    const text: string = new util.TextDecoder().decodeToString(buf);
    DataStore._data = JSON.parse(text) as AppData;
    return DataStore._data;
  }

  static get data(): AppData {
    return DataStore._data as AppData;
  }

  static articleById(id: string): Article | undefined {
    return DataStore._data?.articles.find(a => a.id === id);
  }

  static questionById(id: string): Question | undefined {
    return DataStore._data?.questions.find(q => q.id === id);
  }

  // 全部套题（真题模考列表）
  static sets(): MockSet[] {
    return DataStore._data?.sets ?? [];
  }

  // 按 id 取单套
  static setById(id: string): MockSet | undefined {
    return DataStore._data?.sets.find(s => s.id === id);
  }

  // 取某套的全部题目（保持套内顺序）
  static questionsOfSet(setId: string): Question[] {
    const s: MockSet | undefined = DataStore.setById(setId);
    if (!s) return [];
    const map: Map<string, Question> = new Map(
      (DataStore._data?.questions ?? []).map(q => [q.id, q])
    );
    return s.questionIds
      .map(id => map.get(id))
      .filter((q: Question | undefined): boolean => q !== undefined)
      .map((q: Question | undefined): Question => q as Question);
  }
}

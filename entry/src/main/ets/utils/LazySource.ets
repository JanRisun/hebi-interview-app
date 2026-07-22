// 通用 LazyForEach 数据源：包装任意数组，随 @State 数组变化刷新。
// 用法：
//   @State ds: LazyDataSource<T> = new LazyDataSource<T>([]);
//   // 数据变化后调用：
//   this.ds.setData(newArray);   // 内部通知 List 重新加载
// List 中：LazyForEach(this.ds, (it: T) => { ... }, (it: T) => it.id)
export class LazyDataSource<T> implements IDataSource {
  // 注意：字段必须公开（不能 private）。ArkUI 对 @State 对象做深度观察代理时，
  // 只会枚举/代理可公开访问的属性，私有字段在代理层不可见，会导致 totalCount() 读到
  // undefined 而崩溃。数据源的刷新由 IDataSource 的 onDataReloaded 通知驱动，无需 @State。
  dataArray: T[] = [];
  listeners: DataChangeListener[] = [];

  constructor(initData: T[] = []) {
    this.dataArray = initData;
  }

  totalCount(): number {
    if (!this.dataArray) {
      return 0;
    }
    return this.dataArray.length;
  }

  getData(index: number): T {
    return this.dataArray[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
  }

  // 全量替换并通知（用于搜索过滤 / 数据加载后刷新）
  setData(newData: T[]): void {
    this.dataArray = newData;
    this.notifyDataReload();
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

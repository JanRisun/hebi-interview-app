// 首页标签栏管理：编辑名称、开关显隐、上/下排序
// 编辑作用于本地草稿，点击「完成」才写入 AppStorage 并持久化；返回则放弃改动。
import { common } from '@kit.AbilityKit';
import { TabBarStore, TabItem } from '../utils/TabBarStore';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';

@Entry
@Component
export struct TabBarEditor {
  @Consume pageStack: NavPathStack;
  // 本地草稿：从 AppStorage 当前配置初始化，保存时才回写
  @State draft: TabItem[] = TabBarStore.defaultTabs();

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  aboutToAppear(): void {
    const from = AppStorage.get('tabBarConfig') as TabItem[] | undefined;
    if (from && from.length > 0) {
      this.draft = from.map((t: TabItem): TabItem => ({ key: t.key, label: t.label, visible: t.visible }));
    }
  }

  private visibleCount(): number {
    return this.draft.filter((t: TabItem) => t.visible).length;
  }

  private moveUp(idx: number): void {
    if (idx <= 0) return;
    const arr: TabItem[] = this.draft.slice();
    const tmp: TabItem = arr[idx - 1];
    arr[idx - 1] = arr[idx];
    arr[idx] = tmp;
    this.draft = arr;
  }

  private moveDown(idx: number): void {
    if (idx >= this.draft.length - 1) return;
    const arr: TabItem[] = this.draft.slice();
    const tmp: TabItem = arr[idx + 1];
    arr[idx + 1] = arr[idx];
    arr[idx] = tmp;
    this.draft = arr;
  }

  private toggleVisible(idx: number): void {
    const arr: TabItem[] = this.draft.slice();
    // 至少保留一个可见项
    if (arr[idx].visible && this.visibleCount() <= 1) return;
    arr[idx] = { key: arr[idx].key, label: arr[idx].label, visible: !arr[idx].visible };
    this.draft = arr;
  }

  private onLabelChange(idx: number, v: string): void {
    const arr: TabItem[] = this.draft.slice();
    arr[idx] = { key: arr[idx].key, label: v, visible: arr[idx].visible };
    this.draft = arr;
  }

  private async onSave(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    await TabBarStore.save(ctx, this.draft);
    AppStorage.set('tabBarConfig', this.draft.slice());
    this.pageStack.pop();
  }

  // 单条编辑行
  @Builder
  private row(item: TabItem, idx: number) {
    Row({ space: SPACE.sm }) {
      SymbolGlyph(TabBarStore.icon(item.key))
        .fontSize(22)
        .fontColor([$r('app.color.brand')])
        .margin({ left: SPACE.md, right: SPACE.sm })

      Column() {
        TextInput({ placeholder: '名称', text: item.label })
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => {
            this.onLabelChange(idx, v);
          })
        Text('底部栏显示 · 拖动右侧按钮排序')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: item.visible })
        .onChange(() => {
          this.toggleVisible(idx);
        })
        .margin({ right: SPACE.sm })

      Column({ space: 6 }) {
        Button('↑')
          .width(36)
          .height(30)
          .fontSize(14)
          .enabled(idx > 0)
          .onClick(() => this.moveUp(idx))
        Button('↓')
          .width(36)
          .height(30)
          .fontSize(14)
          .enabled(idx < this.draft.length - 1)
          .onClick(() => this.moveDown(idx))
      }
      .margin({ right: SPACE.md })
    }
    .width('100%')
    .padding({ top: SPACE.md, bottom: SPACE.md })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .margin({ bottom: SPACE.sm })
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
  }

  build() {
    Column() {
      BackHeader({ title: '首页标签栏管理', showAction: true }) {
        Text('完成')
          .fontSize(FONT.body)
          .fontColor($r('app.color.brand'))
          .onClick(() => {
            this.onSave();
          })
      }

      Scroll() {
        Column() {
          Text('可改名、开关是否在底部栏显示（至少保留一个），用 ↑/↓ 调整顺序。')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .width('92%')
            .margin({ bottom: SPACE.sm })

          List() {
            ForEach(this.draft, (item: TabItem, idx: number) => {
              ListItem() {
                this.row(item, idx)
              }
            }, (item: TabItem) => item.key)
          }
          .width('92%')
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    .padding({ top: 0, bottom: this.safeBottom })
  }
}

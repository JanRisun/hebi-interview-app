// 本地知识库：以「索引」方式管理本地文件，不复制实体，保证文件唯一指向。
// 做法：用 DocumentViewPicker / PhotoViewPicker 选择文件，仅保存系统返回的「原始 URI」+ 元数据；
//       点击图片内嵌全屏预览（bindContentCover，返回只关闭预览不退出页面），点击文档用 startAbility 打开原文件。
// 能力：批量选择/删除；图片缩略图区分；列表按 全部/图片/文档 筛选；文件名 URL 解码。
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { BackHeader } from '../utils/BackHeader';
import { EmptyState } from '../utils/Ui';
import { FONT, SPACE, RADIUS, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

type KbType = 'pdf' | 'word' | 'image' | 'other';
type KbFilter = 'all' | 'image' | 'doc';

interface KbItem {
  id: string;
  name: string;
  type: KbType;
  size: number;
  addTime: string;
  uri: string;
}

interface TypeMeta {
  emoji: string;
  color: Resource;
  label: string;
}

const KB_PREF: string = 'kb_pref';
const KB_KEY: string = 'kb_files';

@Component
export struct LocalKnowledgeView {
  @Consume pageStack: NavPathStack;
  @State items: KbItem[] = [];
  @State batchMode: boolean = false;          // 批量选择模式
  @State selectedIds: string[] = [];          // 已选条目 id
  @State showPreview: boolean = false;        // 图片预览浮层（bindContentCover）
  @State previewItem: KbItem | null = null;   // 当前预览的图片
  @State filter: KbFilter = 'all';            // 列表筛选
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  private ctx: common.UIAbilityContext = {} as common.UIAbilityContext;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.UIAbilityContext;
    this.load();
  }

  private load(): void {
    try {
      const p: preferences.Preferences = preferences.getPreferencesSync(this.ctx, { name: KB_PREF });
      const raw: string = p.getSync(KB_KEY, '[]') as string;
      this.items = JSON.parse(raw) as KbItem[];
    } catch (e) {
      this.items = [];
    }
  }

  private save(): void {
    try {
      const p: preferences.Preferences = preferences.getPreferencesSync(this.ctx, { name: KB_PREF });
      p.putSync(KB_KEY, JSON.stringify(this.items));
      p.flush();
    } catch (e) {
      promptAction.showToast({ message: '保存失败' });
    }
  }

  // 当前筛选后的列表
  private getViewItems(): KbItem[] {
    if (this.filter === 'image') {
      return this.items.filter((it: KbItem) => it.type === 'image');
    }
    if (this.filter === 'doc') {
      return this.items.filter((it: KbItem) => it.type !== 'image');
    }
    return this.items;
  }

  // ===== 文件选择（仅取 URI 作为索引，不复制）=====
  private pickDocument(): void {
    try {
      const dp = new picker.DocumentViewPicker(this.ctx);
      dp.select({
        maxSelectNumber: 20,
        fileSuffixFilters: ['.pdf', '.doc', '.docx', '.txt', '.md']
      }).then((uris) => {
        for (const uri of uris) {
          this.addIndex(uri);
        }
      }).catch((err: BusinessError) => {
        if (err.code !== 0) {
          console.error('[KB] document picker error: ' + err.code + ' ' + err.message);
        }
      });
    } catch (e) {
      promptAction.showToast({ message: '无法打开文件选择器' });
    }
  }

  private pickImage(): void {
    try {
      const pp = new picker.PhotoViewPicker(this.ctx);
      pp.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 20
      }).then((res) => {
        for (const uri of res.photoUris) {
          this.addIndex(uri, 'image');
        }
      }).catch((err: BusinessError) => {
        if (err.code !== 0) {
          console.error('[KB] photo picker error: ' + err.code + ' ' + err.message);
        }
      });
    } catch (e) {
      promptAction.showToast({ message: '无法打开图片选择器' });
    }
  }

  private addIndex(srcUri: string, typeHint?: KbType): void {
    try {
      const name: string = this.resolveName(srcUri);
      let size: number = 0;
      try {
        size = fileIo.statSync(srcUri).size;
      } catch (e) {
        // 读不到大小记 0
      }
      const item: KbItem = {
        id: Date.now() + '_' + Math.floor(Math.random() * 100000),
        name: name,
        type: typeHint ?? this.detectType(srcUri),
        size: size,
        addTime: this.formatTime(new Date()),
        uri: srcUri
      };
      this.items = [item, ...this.items];
      this.save();
      promptAction.showToast({ message: '已加入本地知识库（指向原文件）' });
    } catch (e) {
      const msg: string = ((e as Error)?.message ?? '未知错误');
      promptAction.showToast({ message: '添加失败：' + msg });
    }
  }

  // 解析文件名：URI 末段做 URL 解码，失败则生成默认名
  private resolveName(srcUri: string): string {
    const raw: string = srcUri.split('/').pop() ?? '';
    let name: string = raw;
    try {
      name = decodeURIComponent(raw);
    } catch (e) {
      name = raw;
    }
    if (!name || name.indexOf('.') < 0) {
      name = '文件_' + Date.now() + '.' + this.extFor(this.detectType(srcUri));
    }
    return name;
  }

  // ===== 打开 / 预览 =====
  // 图片：内嵌全屏预览（bindContentCover）；文档/其它：调起系统查看器打开原文件
  private openItem(item: KbItem): void {
    if (item.type === 'image') {
      this.previewItem = item;
      this.showPreview = true;
      return;
    }
    this.openExternal(item);
  }

  // 调起系统查看器（best-effort，原 URI 由系统授权）
  private openExternal(item: KbItem): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: item.uri,
        type: this.mimeFor(item),
        flags: 0x00000001 // FLAG_GRANT_READ_URI_PERMISSION
      };
      this.ctx.startAbility(want);
    } catch (e) {
      promptAction.showToast({ message: '无法打开该文件，可能已移动/删除，可删除后重新添加' });
    }
  }

  // 关闭预览；若 Image 加载失败，回退到系统查看器
  private closePreview(fallback?: KbItem): void {
    this.showPreview = false;
    this.previewItem = null;
    if (fallback) {
      this.openExternal(fallback);
    }
  }

  // ===== 删除 =====
  private deleteItem(item: KbItem): void {
    this.items = this.items.filter((it: KbItem) => it.id !== item.id);
    this.selectedIds = this.selectedIds.filter((id: string) => id !== item.id);
    this.save();
  }

  // ===== 批量模式 =====
  private enterBatch(): void {
    this.batchMode = true;
    this.selectedIds = [];
  }

  private exitBatch(): void {
    this.batchMode = false;
    this.selectedIds = [];
  }

  private toggleSelect(item: KbItem): void {
    if (this.selectedIds.includes(item.id)) {
      this.selectedIds = this.selectedIds.filter((id: string) => id !== item.id);
    } else {
      this.selectedIds = [...this.selectedIds, item.id];
    }
  }

  private isSelected(item: KbItem): boolean {
    return this.selectedIds.includes(item.id);
  }

  private allSelected(): boolean {
    return this.items.length > 0 && this.selectedIds.length === this.items.length;
  }

  private selectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.items.map((it: KbItem) => it.id);
    }
  }

  private batchDelete(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    const sel: Set<string> = new Set(this.selectedIds);
    const count: number = this.selectedIds.length;
    this.items = this.items.filter((it: KbItem) => !sel.has(it.id));
    this.selectedIds = [];
    this.batchMode = false;
    this.save();
    promptAction.showToast({ message: `已删除 ${count} 条` });
  }

  // ===== 工具方法 =====
  private detectType(path: string): KbType {
    const lower: string = path.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'pdf';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'word';
    }
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') || lower.endsWith('.bmp') || lower.endsWith('.webp')) {
      return 'image';
    }
    return 'other';
  }

  private extFor(type: KbType): string {
    switch (type) {
      case 'pdf': return 'pdf';
      case 'word': return 'docx';
      case 'image': return 'png';
      default: return 'txt';
    }
  }

  private mimeFor(item: KbItem): string {
    if (item.type === 'pdf') {
      return 'application/pdf';
    }
    if (item.type === 'word') {
      return item.name.toLowerCase().endsWith('.docx')
        ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        : 'application/msword';
    }
    if (item.type === 'image') {
      return 'image/*';
    }
    return 'text/plain';
  }

  private typeMeta(t: KbType): TypeMeta {
    switch (t) {
      case 'pdf': return { emoji: '📕', color: $r('app.color.danger'), label: 'PDF' };
      case 'word': return { emoji: '📘', color: $r('app.color.brand'), label: 'Word' };
      case 'image': return { emoji: '🖼️', color: $r('app.color.success'), label: '图片' };
      default: return { emoji: '📄', color: $r('app.color.text_secondary'), label: '文件' };
    }
  }

  private formatTime(d: Date): string {
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  private formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '—';
    }
    if (bytes < 1024) {
      return bytes + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(1) + ' KB';
    }
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }

  private totalSize(): string {
    let total: number = 0;
    for (const it of this.items) {
      total += it.size;
    }
    return this.formatSize(total);
  }

  // ===== 构建 =====
  // 自绘复选框（避免依赖具体 sys.symbol 名称）
  @Builder
  private checkBox(selected: boolean) {
    Row() {
      if (selected) {
        Text('✓')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_primary'))
      }
    }
    .width(24)
    .height(24)
    .borderRadius(12)
    .backgroundColor(selected ? $r('app.color.brand') : $r('app.color.surface'))
    .border({ width: selected ? 0 : 1, color: $r('app.color.text_tertiary') })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private overviewBar() {
    Row() {
      Column() {
        Text(this.items.length.toString())
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text(this.batchMode ? `已选 ${this.selectedIds.length}` : '条索引')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text(this.totalSize())
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Text('索引大小')
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .margin({ left: SPACE.lg, right: SPACE.lg, top: SPACE.md, bottom: SPACE.md })
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
  }

  @Builder
  private actionBar() {
    Row({ space: SPACE.md }) {
      Button('📄 添加文档', { type: ButtonType.Normal })
        .layoutWeight(1)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.on_primary'))
        .onClick(() => this.pickDocument())
      Button('🖼️ 添加图片', { type: ButtonType.Normal })
        .layoutWeight(1)
        .backgroundColor($r('app.color.accent_2'))
        .fontColor($r('app.color.on_primary'))
        .onClick(() => this.pickImage())
    }
    .width('100%')
    .padding({ left: SPACE.lg, right: SPACE.lg, bottom: SPACE.md })
  }

  // 筛选标签：全部 / 图片 / 文档
  @Builder
  private filterBar() {
    Row({ space: SPACE.sm }) {
      this.filterTab('all', '全部')
      this.filterTab('image', '图片')
      this.filterTab('doc', '文档')
    }
    .width('100%')
    .padding({ left: SPACE.lg, right: SPACE.lg, bottom: SPACE.sm })
  }

  @Builder
  private filterTab(key: KbFilter, label: string) {
    Text(label)
      .fontSize(FONT.caption)
      .fontColor(this.filter === key ? $r('app.color.on_primary') : $r('app.color.text_secondary'))
      .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.xs, bottom: SPACE.xs })
      .backgroundColor(this.filter === key ? $r('app.color.brand') : $r('app.color.surface_variant'))
      .borderRadius(RADIUS.pill)
      .onClick(() => { this.filter = key; })
  }

  @Builder
  private itemRow(item: KbItem) {
    Row() {
      // 左侧：图片显示缩略图，文档显示类型色块 + emoji，清晰区分
      Column() {
        if (item.type === 'image') {
          Image(item.uri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
        } else {
          Text(this.typeMeta(item.type).emoji)
            .fontSize(22)
        }
      }
      .width(44)
      .height(44)
      .borderRadius(12)
      .backgroundColor(item.type === 'image' ? $r('app.color.surface_variant') : this.typeMeta(item.type).color)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 中间：文件名 + 元信息（类型标签内联，避免右侧溢出）
      Column() {
        Text(item.name)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(`${this.formatSize(item.size)}  ·  ${item.addTime}`)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.typeMeta(item.type).label)
            .fontSize(FONT.mini)
            .fontColor(this.typeMeta(item.type).color)
            .fontWeight(FontWeight.Medium)
            .margin({ left: SPACE.sm })
        }
        .width('100%')
        .margin({ top: 4 })
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: SPACE.md })

      // 右侧：批量模式下显示复选框；否则留空，避免内容溢出
      if (this.batchMode) {
        this.checkBox(this.isSelected(item))
      } else {
        Text('›')
          .fontSize(FONT.title)
          .fontColor($r('app.color.text_arrow'))
      }
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor(this.isSelected(item) ? $r('app.color.brand_light') : $r('app.color.surface'))
    .border({
      width: this.isSelected(item) ? 1 : 0,
      color: this.isSelected(item) ? $r('app.color.brand') : Color.Transparent
    })
    .borderRadius(RADIUS.md)
    .margin({ left: SPACE.lg, right: SPACE.lg, bottom: SPACE.sm })
    .shadow({ radius: 8, color: $r('app.color.card_stroke'), offsetY: 1 })
    .onClick(() => {
      if (this.batchMode) {
        this.toggleSelect(item);
      } else {
        this.openItem(item);
      }
    })
  }

  @Builder
  private deleteBuilder(item: KbItem) {
    Button('删除')
      .backgroundColor($r('app.color.danger'))
      .fontColor($r('app.color.on_primary'))
      .onClick(() => this.deleteItem(item))
  }

  // 批量模式底部操作栏（全选 / 删除）
  @Builder
  private batchActionBar() {
    Row() {
      Button(this.allSelected() ? '取消全选' : '全选')
        .layoutWeight(1)
        .height(44)
        .backgroundColor($r('app.color.surface_variant'))
        .fontColor($r('app.color.text_primary'))
        .borderRadius(RADIUS.md)
        .onClick(() => this.selectAll())
      Button(`删除 (${this.selectedIds.length})`)
        .layoutWeight(1)
        .height(44)
        .margin({ left: SPACE.md })
        .backgroundColor(this.selectedIds.length === 0
          ? $r('app.color.surface_variant')
          : $r('app.color.danger'))
        .fontColor(this.selectedIds.length === 0
          ? $r('app.color.text_tertiary')
          : $r('app.color.on_primary'))
        .borderRadius(RADIUS.md)
        .onClick(() => this.batchDelete())
    }
    .width('100%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.sm, bottom: SPACE.sm })
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 1 }, color: $r('app.color.divider') })
  }

  // 图片内嵌预览（bindContentCover 承载：返回只关闭预览、不退出页面）
  @Builder
  private previewBuilder() {
    Column() {
      // 顶部操作栏：带安全区适配，避免按钮贴状态栏
      Row() {
        if (this.previewItem) {
          Text('用系统查看器打开')
            .fontSize(FONT.caption)
            .fontColor($r('app.color.on_primary'))
            .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
            .backgroundColor('#40000000')
            .borderRadius(RADIUS.sm)
            .onClick(() => {
              const it: KbItem | null = this.previewItem;
              this.closePreview();
              if (it) {
                this.openExternal(it);
              }
            })
        }
        Blank()
        Text('✕')
          .fontSize(24)
          .fontColor($r('app.color.on_primary'))
          .padding({ left: SPACE.md, right: SPACE.md, top: SPACE.sm, bottom: SPACE.sm })
          .onClick(() => this.closePreview())
      }
      .width('100%')
      .padding({ top: this.safeTop, left: SPACE.lg, right: SPACE.lg, bottom: SPACE.sm })

      if (this.previewItem) {
        Stack() {
          Image(this.previewItem.uri)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
            .onError(() => {
              const it: KbItem | null = this.previewItem;
              this.closePreview(it ?? undefined);
            })
          Column() {
            Blank()
            Text(this.previewItem.name)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.on_primary'))
              .padding(SPACE.sm)
              .backgroundColor('#80000000')
              .borderRadius(RADIUS.sm)
              .margin({ bottom: SPACE.xl })
          }
          .width('100%')
          .height('100%')
        }
        .layoutWeight(1)
        .onClick(() => this.closePreview())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E6000000')
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
  }

  // 头部右侧操作：进入/退出批量模式
  @Builder
  private headerAction() {
    Text(this.batchMode ? '取消' : '选择')
      .fontSize(FONT.body)
      .fontColor($r('app.color.brand'))
      .onClick(() => {
        if (this.batchMode) {
          this.exitBatch();
        } else {
          this.enterBatch();
        }
      })
  }

  build() {
    Column() {
      BackHeader({ title: '本地知识库', showAction: true, action: this.headerAction })

      this.overviewBar()

      // 批量模式下隐藏添加按钮，避免误操作
      if (!this.batchMode) {
        this.actionBar()
      }

      this.filterBar()

      if (this.getViewItems().length === 0) {
        EmptyState({
          emoji: this.items.length === 0 ? '📚' : '🔍',
          text: this.items.length === 0
            ? '还没有本地资料，点击下方按钮添加 Word / PDF / 图片（仅保存索引，指向原文件）'
            : '该分类下暂无文件'
        })
          .layoutWeight(1)
      } else {
        List() {
          ForEach(this.getViewItems(), (item: KbItem) => {
            ListItem() {
              this.itemRow(item)
            }
            // 批量模式下禁用左滑删除，避免与选择手势冲突；整个 options 置 undefined 以彻底移除滑动
            .swipeAction(!this.batchMode ? { end: () => { this.deleteBuilder(item); } } : undefined)
          }, (item: KbItem) => item.id)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.None)
      }

      if (this.batchMode) {
        this.batchActionBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    .padding({ top: this.safeTop, bottom: this.safeBottom })
    .bindContentCover(this.showPreview, this.previewBuilder)
  }
}

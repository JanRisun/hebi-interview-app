// 收藏与标记二级页：两个 Tab（收藏 / 我的标记），顶部搜索框，点击进入详情。
// 从个人中心「我的收藏」「我的标记」卡 push 进入，由 AppStorage.markInitTab 定位默认 Tab。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Article, Question } from '../model/Types';
import { UserTagStore, PRESET_MARK_TAGS } from '../utils/UserTagStore';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { IconTile, EmptyState, HighlightText } from '../utils/Ui';

// 详情路由参数（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface DetailParam { id: string; kind: string; kw?: string }

// 统一列表项（收藏 / 我的标记 共用）
interface MarkItem {
  id: string;
  kind: string;      // 'article' | 'question'
  title: string;
  sub: string;       // 来源 / 分类
  tags: string[];    // 收藏项为空；标记项为用户标签
}

@Component
export struct MyMarkView {
  @State marks: MarkItem[] = [];   // 我的标记列表（全部带标签内容）
  @State kw: string = '';          // 搜索框内容
  @State activeTab: number = 0;    // 当前标签 Tab 索引（0=全部）
  @Consume pageStack: NavPathStack;

  // 预设标签数组：二级页按这些标签分页展示（与个人中心「我的标记」、详情页悬浮按钮共用）
  private readonly presetTags: string[] = PRESET_MARK_TAGS;

  // 订阅全局收藏/标签版本号：详情页加标签后自动重读，无需重启 app
  @StorageLink('favTagVersion') @Watch('onDataChange') tagVersion: number = 0;

  aboutToAppear(): void {
    AppStorage.set('markInitTab', '');
    this.refreshData();
  }

  // 收藏/标签变更时触发（@Watch）：重读最新数据
  private onDataChange(): void {
    this.refreshData();
  }

  private refreshData(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    DataStore.load(ctx).then(async (d: AppData) => {
      await UserTagStore.init(ctx);
      this.marks = await this.buildMarks(d);
    });
  }

  // 由用户标签映射构建列表项（仅保留有标签的内容）
  private async buildMarks(d: AppData): Promise<MarkItem[]> {
    const map: Record<string, string[]> = await UserTagStore.allMap();
    const list: MarkItem[] = [];
    Object.keys(map).forEach((id) => {
      const tags: string[] = map[id];
      if (!tags || tags.length === 0) return;
      const a: Article | undefined = d.articles.find((x) => x.id === id);
      if (a) {
        list.push({ id, kind: 'article', title: a.title, sub: a.category, tags });
        return;
      }
      const q: Question | undefined = d.questions.find((x) => x.id === id);
      if (q) {
        list.push({ id, kind: 'question', title: q.title, sub: q.source, tags });
      }
    });
    return list;
  }

  // 按关键词过滤（标题 / 来源 / 标签）
  private filterList(src: MarkItem[]): MarkItem[] {
    const k: string = this.kw.trim().toLowerCase();
    if (!k) return src;
    return src.filter((it: MarkItem): boolean => {
      if (it.title.toLowerCase().includes(k)) return true;
      if (it.sub.toLowerCase().includes(k)) return true;
      if (it.tags.some((t: string): boolean => t.toLowerCase().includes(k))) return true;
      return false;
    });
  }

  // 标签分页签：全部 + 预设标签
  private tagTabs(): string[] {
    return ['全部', ...this.presetTags];
  }

  // 取某标签下的标记项（''/'全部' = 全部）
  private itemsOfTag(t: string): MarkItem[] {
    if (t === '全部' || t === '') return this.marks;
    return this.marks.filter((it: MarkItem): boolean => it.tags.includes(t));
  }

  // 某标签下的空态文案
  private emptyTextFor(t: string): string {
    if (t === '全部' || t === '') return '还没有标记，去详情页添加标签吧';
    return `「${t}」下还没有内容`;
  }

  // 进入详情
  private openItem(it: MarkItem): void {
    const params: DetailParam = { id: it.id, kind: it.kind, kw: this.kw };
    this.pageStack.pushPathByName('Detail', params);
  }

  // 列表项行：图标 + 标题 + 副标题 + 标签 chips（标记项）+ 箭头
  @Builder rowItem(it: MarkItem) {
    Row() {
      IconTile({
        emoji: it.kind === 'article' ? '📖' : '❓',
        bg: it.kind === 'article' ? $r('app.color.brand_light') : $r('app.color.accent_soft'),
        fg: it.kind === 'article' ? $r('app.color.brand') : $r('app.color.accent'),
        dim: 44
      })
        .margin({ right: SPACE.md })
      Column() {
        HighlightText({ text: it.title, kw: this.kw, fontSize: FONT.body, baseColor: $r('app.color.text_primary'), hitColor: $r('app.color.brand'), singleLine: true })
          .width('100%')
        HighlightText({ text: `${it.kind === 'article' ? '知识点' : '真题'} · ${it.sub}`, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), hitColor: $r('app.color.brand') })
          .margin({ top: SPACE.xs })
          .width('100%')
        if (it.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(it.tags.slice(0, 3), (t: string) => {
              Text(t)
                .fontSize(FONT.mini)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.xs, right: SPACE.xs })
            }, (t: string) => t)
            if (it.tags.length > 3) {
              Text('+' + (it.tags.length - 3))
                .fontSize(FONT.mini)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: SPACE.xs })
            }
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(FONT.title)
        .fontColor($r('app.color.text_arrow'))
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.md)
    .margin({ bottom: SPACE.sm })
    .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })
    .onClick(() => this.openItem(it))
  }

  @Builder tabList(list: MarkItem[], emptyText: string) {
    // TabContent 默认会把子组件垂直居中且不拉伸，需显式撑满并贴顶
    Column() {
      if (list.length === 0) {
        EmptyState({ emoji: '🤍', text: emptyText })
      } else {
        List() {
          ForEach(list, (it: MarkItem) => {
            ListItem() {
              this.rowItem(it)
            }
          }, (it: MarkItem) => it.id)
        }
        .width('92%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(list.length === 0 ? FlexAlign.Center : FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 子页头部（带返回）
      BackHeader({ title: '我的标记' })

      // 顶部搜索框（胶囊形 + 搜索图标），输入即在本页跨标签实时检索
      Row() {
        Text('🔍')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: SPACE.md, right: SPACE.sm })
        TextInput({ placeholder: '搜索标题 / 来源 / 标签', text: this.kw })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.transparent'))
          .padding({ left: SPACE.sm })
          .onChange((v: string) => {
            this.kw = v;
          })
        if (this.kw) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ right: SPACE.md })
            .onClick(() => {
              this.kw = '';
            })
        }
      }
      .width('92%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.pill)
      .margin({ bottom: SPACE.sm })
      .shadow({ radius: 10, color: $r('app.color.card_stroke'), offsetY: 2 })

      if (this.kw.trim()) {
        // 检索态：跨标签展示命中结果（隐藏 Tab）
        if (this.filterList(this.marks).length === 0) {
          EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw.trim()}」的标记` })
        } else {
          List() {
            ForEach(this.filterList(this.marks), (it: MarkItem) => {
              ListItem() {
                this.rowItem(it)
              }
            }, (it: MarkItem) => it.id)
          }
          .width('92%')
          .layoutWeight(1)
          .alignSelf(ItemAlign.Center)
          .margin({ top: SPACE.sm })
        }
      } else {
        // 浏览态：全部 + 6 个标签 Tab 切换
        Tabs({ index: this.activeTab, barPosition: BarPosition.Start }) {
          ForEach(this.tagTabs(), (t: string) => {
            TabContent() {
              this.tabList(this.itemsOfTag(t), this.emptyTextFor(t))
            }.tabBar(t)
          }, (t: string) => t)
        }
        .width('100%')
        .layoutWeight(1)
        .barMode(BarMode.Scrollable)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    // 我的标记是整屏 NavDestination，进入后首页悬浮 Tab 栏已隐藏，底部只留系统安全区
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

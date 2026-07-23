// 真题库二级页：顶部搜索框 + 下方真题列表（平铺，可搜索）
// 从个人中心「真题库」卡 push 进入，返回走 BackHeader；点击真题进入 Detail。
import { common } from '@kit.AbilityKit';
import { DataStore } from '../model/DataStore';
import { AppData, Question } from '../model/Types';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { IconTile, EmptyState, HighlightText } from '../utils/Ui';

// 详情路由参数（规避 arkts-no-untyped-obj-literals：字面量必须对应显式声明的接口）
interface DetailParam { id: string; kind: string; kw?: string }

@Component
export struct QuestionBankView {
  @State data: AppData | null = null;
  @State kw: string = '';          // 搜索框内容（空=显示全部真题，非空=知识点内全文检索）
  @Consume pageStack: NavPathStack;

  aboutToAppear(): void {
    DataStore.load(getContext(this) as common.UIAbilityContext).then((d: AppData) => {
      this.data = d;
    });
  }

  // 真题内全文检索：标题 / 来源 / 题型 / 标签 / 题干
  private matchQuestion(q: Question, k: string): boolean {
    const s: string = k.toLowerCase();
    if (q.title.toLowerCase().includes(s)) return true;
    if (q.source.toLowerCase().includes(s)) return true;
    if (q.type.toLowerCase().includes(s)) return true;
    if (q.tags.some((t: string): boolean => t.toLowerCase().includes(s))) return true;
    if (q.prompt.toLowerCase().includes(s)) return true;
    return false;
  }

  // 当前检索命中结果（kw 为空时返回全部）
  private searchHits(): Question[] {
    if (!this.data) return [];
    const q: string = this.kw.trim();
    if (!q) return this.data.questions;
    return this.data.questions.filter((x: Question): boolean => this.matchQuestion(x, q));
  }

  // 进入真题详情
  private openQuestion(q: Question): void {
    const params: DetailParam = { id: q.id, kind: 'question', kw: this.kw };
    this.pageStack.pushPathByName('Detail', params);
  }

  // 真题行：图标 + 标题 + 来源 + 标签 chips（最多 3 个）+ 箭头
  @Builder questionRow(q: Question) {
    Row() {
      IconTile({ emoji: '❓', bg: $r('app.color.accent_soft'), fg: $r('app.color.accent'), dim: 44 })
        .margin({ right: SPACE.md })
      Column() {
        HighlightText({ text: q.title, kw: this.kw, fontSize: FONT.body, baseColor: $r('app.color.text_primary'), hitColor: $r('app.color.brand'), singleLine: true })
          .width('100%')
        HighlightText({ text: q.source, kw: this.kw, fontSize: FONT.caption, baseColor: $r('app.color.text_secondary'), hitColor: $r('app.color.brand'), singleLine: true })
          .margin({ top: SPACE.xs })
          .width('100%')
        if (q.tags && q.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(q.tags.slice(0, 3), (t: string) => {
              Text(t)
                .fontSize(FONT.mini)
                .fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(RADIUS.sm)
                .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
                .margin({ top: SPACE.xs, right: SPACE.xs })
            }, (t: string) => t)
            if (q.tags.length > 3) {
              Text('+' + (q.tags.length - 3))
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
    .onClick(() => this.openQuestion(q))
  }

  // 真题列表（含检索态空态）
  @Builder list() {
    if (this.searchHits().length === 0) {
      EmptyState({ emoji: '🔍', text: `没有匹配「${this.kw.trim()}」的真题` })
    } else {
      List() {
        ForEach(this.searchHits(), (q: Question) => {
          ListItem() {
            this.questionRow(q)
          }
        }, (q: Question) => q.id)
      }
      .width('92%')
      .layoutWeight(1)
      .alignSelf(ItemAlign.Center)
      .margin({ top: SPACE.sm })
    }
  }

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;

  build() {
    Column() {
      // 子页头部（带返回）
      BackHeader({ title: '真题库' })

      // 顶部搜索框（胶囊形 + 搜索图标），输入即在本页真题内实时检索
      Row() {
        Text('🔍')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: SPACE.md, right: SPACE.sm })
        TextInput({ placeholder: '搜索真题', text: this.kw })
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

      if (this.data) {
        this.list()
      } else {
        EmptyState({ emoji: '⏳', text: '加载中…' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

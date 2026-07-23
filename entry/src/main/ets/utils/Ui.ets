// 通用 UI 组件库：统一全站视觉语言（图标、标签、分区标题、数据卡、空态、进度环、页面品牌头部）
// 用法：import { IconTile, TagChip, SectionTitle, StatCard, EmptyState, ProgressRing, PageHero } from '../utils/Ui';
import { RADIUS, SPACE, FONT, SAFE_AREA_TYPES } from './Theme';

// 彩色圆角图标块：用 emoji + 品牌色底，避免依赖外部图标资源
@Component
export struct IconTile {
  @Prop emoji: string = '•';
  @Prop bg: Resource = $r('app.color.brand_light');
  @Prop fg: Resource = $r('app.color.brand');
  @Prop dim: number = 44;   // 尺寸（不能用 size：与 CustomComponent 内置属性冲突）

  build() {
    Column() {
      Text(this.emoji)
        .fontSize(this.dim * 0.46)
        .fontColor(this.fg)
    }
    .width(this.dim)
    .height(this.dim)
    .borderRadius(this.dim * 0.3)
    .backgroundColor(this.bg)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// 标签芯片：选中→品牌实心，未选中→浅底品牌字
@Component
export struct TagChip {
  @Prop text: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Text(this.text)
      .fontSize(FONT.caption)
      .fontColor(this.selected ? $r('app.color.on_primary') : $r('app.color.brand'))
      .backgroundColor(this.selected ? $r('app.color.brand') : $r('app.color.tag_bg'))
      .borderRadius(RADIUS.sm)
      .padding({ left: SPACE.sm, right: SPACE.sm, top: SPACE.xs, bottom: SPACE.xs })
      .onClick(() => {
        this.onTap();
      })
  }
}

// 分区标题：左侧标题+副标题，右侧可放操作（@BuilderParam）
@Component
export struct SectionTitle {
  @Prop title: string = '';
  @Prop sub: string = '';
  @BuilderParam action: () => void = this.emptyAction;

  @Builder
  emptyAction() {
  }

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(FONT.title)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
        if (this.sub) {
          Text(this.sub)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      this.action()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: SPACE.sm })
  }
}

// 数据卡：大字数值 + 单位 + 标签（用于学习概览/连续天数/进度）
@Component
export struct StatCard {
  @Prop label: string = '';
  @Prop value: string = '0';
  @Prop unit: string = '';
  @Prop accent: Resource = $r('app.color.brand');

  build() {
    Column() {
      Row() {
        Text(this.value)
          .fontSize(FONT.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accent)
        if (this.unit) {
          Text(this.unit)
            .fontSize(FONT.caption)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 3, top: 8 })
        }
      }
      Text(this.label)
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: SPACE.xs })
    }
    .width('100%')
    .padding(SPACE.lg)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(RADIUS.lg)
    .alignItems(HorizontalAlign.Start)
    .shadow({ radius: 12, color: $r('app.color.card_stroke'), offsetY: 3 })
  }
}

// 空态：图标 + 提示文字
@Component
export struct EmptyState {
  @Prop emoji: string = '📭';
  @Prop text: string = '暂无内容';

  build() {
    Column() {
      Text(this.emoji)
        .fontSize(40)
      Text(this.text)
        .fontSize(FONT.bodySm)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: SPACE.sm })
    }
    .width('100%')
    .padding({ top: SPACE.xl, bottom: SPACE.xl })
    .alignItems(HorizontalAlign.Center)
  }
}

// 环形进度（用于学习完成度/打卡）
@Component
export struct ProgressRing {
  @Prop value: number = 0;
  @Prop total: number = 1;
  @Prop dim: number = 64;   // 尺寸（不能用 size：与 CustomComponent 内置属性冲突）
  @Prop color: Resource = $r('app.color.brand');

  build() {
    Progress({ value: this.value, total: this.total, type: ProgressType.Ring })
      .width(this.dim)
      .height(this.dim)
      .color(this.color)
      .style({ strokeWidth: this.dim * 0.12 })
  }
}

// 通用页面头部：纯色大标题，紧贴状态栏下方
// 安全区由外层根 Column 的 expandSafeArea + padding(top: safeTop) 统一管理，PageHeader 自身不处理
@Component
export struct PageHeader {
  @Prop title: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.xs, bottom: SPACE.sm })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.background'))
  }
}

// 页面品牌头部：渐变底 + 图标 + 大标题 + 副标题，用于各 Tab 页顶部，替代孤零零的标题文字
@Component
export struct PageHero {
  @Prop emoji: string = '📚';
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column() {
      Row() {
        IconTile({ emoji: this.emoji, bg: $r('app.color.on_primary'), fg: $r('app.color.brand'), dim: 48 })
        Column() {
          Text(this.title)
            .fontSize(FONT.display)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_primary'))
          if (this.subtitle) {
            Text(this.subtitle)
              .fontSize(FONT.caption)
              .fontColor($r('app.color.on_primary'))
              .opacity(0.85)
              .margin({ top: 4 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: SPACE.md })
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('92%')
    .padding({ top: SPACE.xl, bottom: SPACE.lg })
    .backgroundColor($r('app.color.brand'))
    .linearGradient({ angle: 135, colors: [[$r('app.color.brand'), 0], [$r('app.color.brand_dark'), 1]] })
    .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: RADIUS.lg, bottomRight: RADIUS.lg })
    .expandSafeArea(SAFE_AREA_TYPES, [SafeAreaEdge.TOP])
  }
}

// 高亮片段：命中片段 hit=true
export interface HighlightSeg {
  t: string;
  hit: boolean;
}

// 将文本按关键词拆分为片段，供 HighlightText 拼接高亮
export function splitHighlight(text: string, kw: string): HighlightSeg[] {
  const res: HighlightSeg[] = [];
  const k: string = (kw || '').trim();
  if (!k || !text) {
    res.push({ t: text ?? '', hit: false });
    return res;
  }
  const lower: string = text.toLowerCase();
  const lk: string = k.toLowerCase();
  let i: number = 0;
  while (i < text.length) {
    const idx: number = lower.indexOf(lk, i);
    if (idx < 0) {
      res.push({ t: text.substring(i), hit: false });
      break;
    }
    if (idx > i) {
      res.push({ t: text.substring(i, idx), hit: false });
    }
    res.push({ t: text.substring(idx, idx + lk.length), hit: true });
    i = idx + lk.length;
  }
  return res;
}

// 关键词高亮文本：命中片段用 hitColor 加粗，其余用 baseColor；singleLine 控制单行省略
@Component
export struct HighlightText {
  @Prop text: string = '';
  @Prop kw: string = '';
  @Prop fontSize: number = 15;
  @Prop baseColor: Resource = $r('app.color.text_primary');
  @Prop hitColor: Resource = $r('app.color.brand');
  @Prop baseWeight: number = FontWeight.Normal;
  @Prop singleLine: boolean = false;

  @Builder
  highlightContent() {
    ForEach(splitHighlight(this.text, this.kw),
      (s: HighlightSeg) => {
        Span(s.t)
          .fontSize(this.fontSize)
          .fontColor(s.hit ? this.hitColor : this.baseColor)
          .fontWeight(s.hit ? FontWeight.Bold : this.baseWeight)
      },
      (s: HighlightSeg, idx: number) => idx + '_' + s.t)
  }

  build() {
    if (this.singleLine) {
      Text() {
        this.highlightContent()
      }
      .width('100%')
      .textAlign(TextAlign.Start)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else {
      Text() {
        this.highlightContent()
      }
      .width('100%')
      .textAlign(TextAlign.Start)
    }
  }
}

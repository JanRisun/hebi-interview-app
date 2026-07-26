// 设置页（从个人中心「设置」入口进入）
//   - 外观：跟随系统 / 浅色 / 深色（ApplicationContext.setColorMode 全局生效）
//   - 文字大小：标准 / 大 / 特大（实时预览，FONT getter 随 AppStorage('fontScale') 变化）
//   - 通知：每日备考提醒开关（复用既有提醒逻辑）
//   - 数据：清除学习记录 / 清除我的标记
//   - 关于：版本信息
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { FONT, RADIUS, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';
import { BackHeader } from '../utils/BackHeader';
import { IconTile } from '../utils/Ui';
import {
  getThemeMode,
  getFontLevel,
  setThemeMode,
  setFontLevel,
  ThemeMode
} from '../utils/SettingsStore';
import { UserTagStore } from '../utils/UserTagStore';
import { publishDailyReminder } from '../utils/ReminderHelper';

// 分段按钮（外观 / 字号共用）：用独立组件 + @Prop selected，保证选中态可靠随 @State 重渲染
@Component
struct SegButton {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(FONT.bodySm)
        .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selected ? $r('app.color.on_primary') : $r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selected ? $r('app.color.brand') : $r('app.color.surface_variant'))
    .borderRadius(RADIUS.sm)
    .onClick(() => this.onTap())
  }
}

// 分组卡片：标题 + 内容构建器（用 @BuilderParam 接收内容，避免 @Builder 方法无法承载构建器参数）
@Component
struct GroupCard {
  title: string = '';
  @BuilderParam content: () => void;

  build() {
    Column() {
      Text(this.title)
        .fontSize(FONT.caption)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: SPACE.sm, left: SPACE.xs })
      Column() {
        this.content();
      }
      .width('100%')
      .padding(SPACE.md)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(RADIUS.lg)
      .shadow({ radius: 8, color: $r('app.color.card_stroke'), offsetY: 2 })
    }
    .width('100%')
    .margin({ bottom: SPACE.md })
    .alignItems(HorizontalAlign.Start)
  }
}

// 操作行（点击触发确认弹窗），弹窗用 AlertDialog.show 直接在点击时弹出，避免对 @Builder 结果链式调用 .alert()
@Component
struct ActionRow {
  emoji: string = '';
  bg: Resource = $r('app.color.brand_light');
  fg: Resource = $r('app.color.brand');
  title: string = '';
  sub: string = '';
  alertTitle: string = '';
  alertMessage: string = '';
  confirmAction: () => void = () => {};

  build() {
    Row() {
      IconTile({ emoji: this.emoji, bg: this.bg, fg: this.fg, dim: 42 })
        .margin({ right: SPACE.md })
      Column() {
        Text(this.title)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.sub)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
          .width('100%')
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
    .onClick(() => {
      AlertDialog.show({
        title: this.alertTitle,
        message: this.alertMessage,
        confirm: { value: '清除', action: () => this.confirmAction() },
        cancel: () => {}
      })
    })
  }
}

@Component
export struct SettingsView {
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  // 订阅字号变化，触发本页重渲染（FONT getter 实时读取 AppStorage('fontScale')）
  @StorageProp('fontScale') _fs: number = 1;

  @State themeMode: ThemeMode = 'system';
  @State fontLevel: number = 0;
  @State remindOn: boolean = false;
  @Consume pageStack: NavPathStack;

  private readonly themeOpts: string[] = ['system', 'light', 'dark'];
  private readonly themeLabels: string[] = ['跟随系统', '浅色', '深色'];

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    getThemeMode(ctx).then((m) => { this.themeMode = m; });
    getFontLevel(ctx).then((l) => { this.fontLevel = l; });
    preferences.getPreferences(ctx, 'practice').then((p) => {
      this.remindOn = (p.getSync('plan_remind_on', false) as boolean);
    });
  }

  private onTheme(idx: number): void {
    const mode: ThemeMode = this.themeOpts[idx] as ThemeMode;
    this.themeMode = mode;
    setThemeMode(getContext(this) as common.UIAbilityContext, mode);
  }

  private onFont(idx: number): void {
    this.fontLevel = idx;
    setFontLevel(getContext(this) as common.UIAbilityContext, idx);
  }

  private onRemind(on: boolean): void {
    this.remindOn = on;
    const ctx = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(ctx, 'practice').then((p) => {
      p.putSync('plan_remind_on', on);
      p.flush();
      if (on) {
        const h: number = (p.getSync('plan_remind_hour', 20) as number);
        const m: number = (p.getSync('plan_remind_min', 0) as number);
        publishDailyReminder(ctx, h, m).then((id: number) => {
          if (id > 0) {
            p.putSync('plan_remind_id', id);
            p.flush();
          }
        });
      } else {
        const id: number = (p.getSync('plan_remind_id', -1) as number);
        if (id > 0) {
          try {
            reminderAgentManager.cancelReminder(id);
          } catch (e) {
            // 忽略
          }
        }
      }
    });
  }

  private doClearRecords(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(ctx, 'practice').then((p) => {
      p.deleteSync('r_ids');
      p.deleteSync('sess_ids');
      p.flush();
    });
  }

  private doClearMarks(): void {
    UserTagStore.clearAll();
  }

  // 开关行
  @Builder switchRow(emoji: string, bg: Resource, fg: Resource, title: string, sub: string, isOn: boolean, onChanged: (v: boolean) => void) {
    Row() {
      IconTile({ emoji, bg, fg, dim: 42 })
        .margin({ right: SPACE.md })
      Column() {
        Text(title)
          .fontSize(FONT.body)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(sub)
          .fontSize(FONT.caption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: SPACE.xs })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((v: boolean) => onChanged(v))
    }
    .width('100%')
    .padding({ top: SPACE.sm, bottom: SPACE.sm })
  }

  build() {
    Column() {
      BackHeader({ title: '设置' })
      Scroll() {
        Column() {
          // 外观
          GroupCard({ title: '外观' }) {
            Row() {
              ForEach(this.themeOpts, (opt: string, i: number) => {
                SegButton({ label: this.themeLabels[i], selected: this.themeMode === opt, onTap: () => this.onTheme(i) });
              }, (opt: string, i: number) => opt + i)
            }
            .width('100%')
            .padding(SPACE.xs)
            .backgroundColor($r('app.color.surface_variant'))
            .borderRadius(RADIUS.sm)
          }

          // 文字大小
          GroupCard({ title: '文字大小' }) {
            Row() {
              ForEach(['标准', '大', '特大'], (lab: string, i: number) => {
                SegButton({ label: lab, selected: this.fontLevel === i, onTap: () => this.onFont(i) });
              }, (lab: string, i: number) => lab + i)
            }
            .width('100%')
            .padding(SPACE.xs)
            .backgroundColor($r('app.color.surface_variant'))
            .borderRadius(RADIUS.sm)
            // 实时预览（FONT 随 fontScale 变化）
            Text('面试是综合性考试，既要知其然，也要知其所以然。')
              .fontSize(FONT.body)
              .fontColor($r('app.color.text_body'))
              .width('100%')
              .margin({ top: SPACE.md })
          }

          // 通知
          GroupCard({ title: '通知' }) {
            this.switchRow('🔔', $r('app.color.brand_light'), $r('app.color.brand'),
              '每日备考提醒', '每天固定时间推送复习提醒', this.remindOn, (v: boolean) => this.onRemind(v))
          }

          // 数据
          GroupCard({ title: '数据' }) {
            Column() {
              ActionRow({
                emoji: '🧹',
                bg: $r('app.color.accent_soft'),
                fg: $r('app.color.accent'),
                title: '清除学习记录',
                sub: '删除自评与真题演练记录',
                alertTitle: '清除学习记录',
                alertMessage: '将删除全部自评与真题演练记录，且不可恢复。',
                confirmAction: () => this.doClearRecords()
              })
              ActionRow({
                emoji: '🏷️',
                bg: $r('app.color.brand_light'),
                fg: $r('app.color.brand'),
                title: '清除我的标记',
                sub: '删除全部自定义标签',
                alertTitle: '清除我的标记',
                alertMessage: '将删除所有内容上的自定义标记，且不可恢复。',
                confirmAction: () => this.doClearMarks()
              })
            }
            .width('100%')
          }

          // 关于
          GroupCard({ title: '关于' }) {
            Row() {
              IconTile({ emoji: '📱', bg: $r('app.color.brand_light'), fg: $r('app.color.brand'), dim: 42 })
                .margin({ right: SPACE.md })
              Column() {
                Text('鹤壁面试通')
                  .fontSize(FONT.body)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                Text('版本 1.0.0 · 备考资料本地存储')
                  .fontSize(FONT.caption)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: SPACE.xs })
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ top: SPACE.sm, bottom: SPACE.sm })
          }
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .key(this._fs.toString())
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
    .padding({ top: this.safeTop, bottom: this.safeBottom })
  }
}

// 每日备考提醒（代理提醒）共享逻辑：构建并发布 ReminderRequestAlarm，
// 供 StudyPlan 页面（用户拨开关/改时间）与 EntryAbility（App 启动/回前台兜底）复用，
// 避免请求构建逻辑重复、漂移。
// 注意：HarmonyOS NEXT 真机上 publishReminder 需 AppGallery Connect 开通「代理提醒开放能力」，
// 否则会进入 catch（仅日志，不阻塞）；模拟器(API 20+)免审可直接弹。
import { common, bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x1000;
const TAG: string = 'ReminderHelper';

// 与 StudyPlan.ets 共用的偏好存储键（必须一致，否则读不到已保存的开关/时刻/任务ID）
export const REMIND_NOTIFY_ID: number = 1001; // 固定通知 ID，重复发布自动覆盖
const PREF_NAME: string = 'practice';
const KEY_REMIND_ON: string = 'plan_remind_on';
const KEY_REMIND_HOUR: string = 'plan_remind_hour';
const KEY_REMIND_MIN: string = 'plan_remind_min';
const KEY_REMIND_ID: string = 'plan_remind_id';

// 构建每日代理提醒请求（与 StudyPlan.ets 原 doPublish 内联请求保持完全一致）
function buildRequest(hour: number, minute: number): reminderAgentManager.ReminderRequestAlarm {
  const pkg: string = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).appInfo.name;
  return {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
    hour: hour,
    minute: minute,
    daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
    actionButton: [
      { title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }
    ],
    wantAgent: {
      pkgName: pkg,
      abilityName: 'EntryAbility'
    },
    title: '面试备考提醒',
    content: '今日素材 + 知识 + 1 套套题已就绪，点击开始',
    notificationId: REMIND_NOTIFY_ID,
    slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
    ringDuration: 5
  };
}

// 发布每日提醒，返回系统分配的任务 ID（>0 成功）；失败返回 -1（日志已输出）
export function publishDailyReminder(ctx: common.UIAbilityContext, hour: number, minute: number): Promise<number> {
  const req: reminderAgentManager.ReminderRequestAlarm = buildRequest(hour, minute);
  return reminderAgentManager.publishReminder(req)
    .then((id: number): number => {
      hilog.info(DOMAIN, TAG, '发布每日提醒成功 id=%{public}d', id);
      return id;
    })
    .catch((err: BusinessError): number => {
      hilog.error(DOMAIN, TAG, '发布每日提醒失败 code=%{public}d msg=%{public}s', err.code, err.message);
      return -1;  // 失败标记，调用方用 id > 0 判断
    });
}

// App 启动/回前台兜底：只要曾开启提醒(on=true)，就按已保存时刻重新发布。
// 固定 notificationId=1001 会自动覆盖旧任务，重复调用无害；
// 用于防止系统提醒服务重置/应用数据清理/强杀后系统丢弃任务，导致不再弹通知。
// 真机未开通 AGC「代理提醒开放能力」时必走 catch（仅日志，不阻塞业务）。
export function ensureReminder(ctx: common.UIAbilityContext): void {
  preferences.getPreferences(ctx, PREF_NAME).then((p: preferences.Preferences): void => {
    const on: boolean = p.getSync(KEY_REMIND_ON, false) as boolean;
    if (!on) {
      return; // 未开启，无需兜底
    }
    const hour: number = p.getSync(KEY_REMIND_HOUR, 20) as number;
    const minute: number = p.getSync(KEY_REMIND_MIN, 0) as number;
    publishDailyReminder(ctx, hour, minute)
      .then((newId: number): void => {
        p.putSync(KEY_REMIND_ID, newId);
      })
      .catch((): void => {
        // 失败日志已在 publishDailyReminder 内输出
      });
  }).catch((err: BusinessError): void => {
    hilog.error(DOMAIN, TAG, '读取提醒配置失败 %{public}s', JSON.stringify(err));
  });
}

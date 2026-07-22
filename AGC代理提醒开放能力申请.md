# 真机「代理提醒」开放能力申请清单（HarmonyOS NEXT / reminderAgentManager）

## 为什么需要

`reminderAgentManager.publishReminder` 在 **真机** 上要求应用在 AppGallery Connect（AGC）开通「代理提醒」开放能力，
否则发布被系统拒绝、仅 hilog 报 `发布每日提醒失败 code=17xxxxx`，通知不弹。
模拟器（API 20+）免审，可直接验证代码逻辑。

本项目「每日备考提醒」用的就是代理提醒，所以真机哑火、模拟器能弹，是这个门槛导致的。

## 前置条件

- 华为开发者账号（已实名）
- 应用已在 AGC 创建，且 **包名与工程 `bundleManager` 读取的 `appInfo.name`（即工程 bundleName）一致**
- 已配置签名（调试/发布证书）

## 申请步骤

1. 登录 AppGallery Connect
   https://developer.huawei.com/consumer/cn/service/josp/agc/index.html
2. 「我的项目」→ 选择应用 `hebi-interview-app`（或对应包名）
3. 在项目内找到 **「代理提醒」/「提醒开放能力」** 入口
   （AGC 改版后路径可能变动，可在项目设置里搜索「代理提醒」）
4. 点击「申请开通 / 开通开放能力」，按提示提交（可能需填写应用场景说明：每日备考定时提醒）
5. 等待审核（约 10 个工作日；通过后能力即时生效）
6. 用 **AGC 签发的证书** 重新签名打包
   （debug 包也建议用 AGC 测试证书，确保能力正确绑定到应用）
7. 真机安装后，拨开「每日备考提醒」开关，到设定时间验证通知是否弹出

## 验证是否生效

- DevEco 连真机，Log 过滤 `tag:ReminderHelper`
  - 见到 `发布每日提醒成功 id=...` → 能力已生效，到时间应弹通知
  - 仍见 `发布每日提醒失败 code=17xxxxx` → 能力未生效或未绑定证书
- 反向验证代码逻辑：改用模拟器跑，把提醒时间设成 1 分钟后等待，能弹即证明代码本身没问题

## 注意事项

- **包名必须和 AGC 应用完全一致**，否则能力绑不上
- 代理提醒受系统勿扰 / 通知权限影响：设置里给应用开通知权限；测试时关掉勿扰模式
- `slotType: SOCIAL_COMMUNICATION` 类通知在勿扰模式下会被静默（感觉"没响"其实是被压住）
- 本工程已做兜底：App 每次回前台（`EntryAbility.onForeground`）会按已保存时刻重新发布，
  可缓解"系统任务丢失后不再弹"的问题；但真机授权门槛（AGC 能力）仍需上述申请解决

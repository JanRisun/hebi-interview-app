# 结构化面试备考 · 鸿蒙 APP

一个**纯离线、无后端**的个人复习应用，把全部面试备考资料（总册、真题逐字稿、专项练习、考场贴士要点）结构化后装进手机。基于 HarmonyOS NEXT（Stage 模型，ArkTS + ArkUI），主打**底部 4 Tab 导航 + 真题套题模考 + 速记卡 + 个人学习档案 + 语音播报 + 开口自测转写 + 备考计划每日提醒**，随时随地复习。

## 功能

| 模块 | 说明 |
|------|------|
| **素材**（分类浏览） | 知识点按分类分组；真题按来源列出；顶部搜索框做全文检索 |
| **速记卡** | 大卡片点按翻转看要点；**左滑**下一题、**右滑**进入收藏 |
| **真题模考** | 四阶段流程：选题 → 模考 → 复盘 → 报告；支持多套套题与随机抽题；复盘前隐藏逐字稿，复盘时才展开参考答案；**结构化分段计时**（思考 → 作答 → 超时）到点**振动提示**；支持**开口自测录音 + 端侧语音转写** |
| **个人中心** | 四个入口：我的收藏、我的学习记录、我的真题演练记录、备考计划（后三者为独立子页，均带搜索 + 返回） |
| **语音播报（TTS）** | 基于 `@kit.CoreSpeechKit` 的全文 / 题目 / 解析朗读；详情页朗读按钮 + 可拖拽悬浮播控条（暂停 / 继续 / 进度 / 关闭），按句切分实现稳定播报 |
| **开口自测转写（ASR）** | 录音条用 `@kit.AudioKit` 的 `AudioCapturer` 直录 **PCM 16k/单声道/16bit** 写 WAV，经 `@kit.CoreSpeechKit` 的 `speechRecognizer` 端侧转写为文字（零密钥、纯本地），便于对照逐字稿自检口述 |
| **开口自测・音频作答回放** | 详情页「开始答题」选音频作答 → `AudioAnswer` 页用 `AudioCapturer` 直录 PCM 写 WAV，实时渲染录音波形；录完用 `AVPlayer`（`fdSrc` 原生解码，干净无噪）回放，支持播放 / 暂停 / 进度拖拽 / 重录；提交后由本地模型生成针对性点评 |
| **备考计划 + 每日提醒** | 设目标考试日 → 显示「距考试 N 天」倒计时 + 进度；按面试题型模块生成可勾选复习清单（完成率进度条，支持增删）；开启**每日备考提醒**后，系统代理每天定点推送通知，点开直达「今日备考」区块（按日期轮取素材 + 知识 + 1 套题） |
| 全文检索 | 关键词搜标题 / 正文 / 标签，按命中权重排序（Search 页支持 `q` 参数直达） |
| 我的收藏 / 记录 | 基于 `@kit.ArkData` Preferences 持久化，重进不丢；支持搜索过滤 |

## 技术栈

- HarmonyOS NEXT（**Stage 模型**，**API 20 / HarmonyOS 6**，声明式 ArkUI）
- 导航：`Tabs`（底部 4 Tab）+ `router.pushUrl`（子页用 `params` 对象传参，`router.back()` 返回）；备考计划每日提醒通知经 `EntryAbility` 的 `onCreate` / `onNewWant` 写 `AppStorage` → `Index` 自动直达
- 数据：`resources/rawfile/data.json`（结构化 JSON，离线内置）
- 持久化：收藏 / 自评记录 / 模考记录 / 备考计划（考试日、任务清单、提醒开关与时间）均用 `@kit.ArkData` Preferences
- 语音：`@kit.CoreSpeechKit`（TTS `TextToSpeechEngine` + ASR `speechRecognizer`）、`@kit.AudioKit`（`AudioCapturer` 直录 PCM）
- 定时提醒：`@kit.BackgroundTasksKit` 的 `reminderAgentManager`（系统代理提醒，App 退后台 / 被杀仍照常推送）
- 振动提示：`@kit.SensorServiceKit` 的 `vibrator`（受声音模式管控）
- 检索：纯前端本地全文匹配，无需联网

## 设计系统（Design Tokens + 深浅模式）

按 HarmonyOS Design 规范做了统一视觉，全部随系统深浅自动切换：

- **颜色语义 Token**：集中在 `resources/base/element/color.json`（浅色）与 `resources/dark/element/color.json`（深色），页面统一通过 `$r('app.color.*')` 引用。主色沿用品牌蓝。
- **字号 / 间距 / 圆角常量**：集中在 `entry/src/main/ets/utils/Theme.ets`（`FONT` / `SPACE` / `RADIUS`），全局复用，避免魔法数字。
- **深色模式**：跟随系统设置，资源系统自动在 base↔dark 间切换；`EntryAbility` 另将当前 `colorMode` 同步进 `AppStorage`。
- **图标**：底部 Tab 与列表入口用系统 **SymbolGlyph**（矢量、随字重缩放、选中态高亮品牌色）；UI 文案不使用 emoji（避免字体渲染异常），统一用单汉字 / 纯文字图标。

## 导入与运行（需在本地完成）

> 以下必须在你本地的 **DevEco Studio** 中完成。当前环境没有 DevEco / 鸿蒙 SDK / 签名证书，无法在此编译打包。

1. 安装 DevEco Studio（HarmonyOS NEXT 版本），配置 HarmonyOS SDK（**API 20**）。
2. 打开 DevEco Studio → Open → 选择本目录 `HebiInterviewApp`（识别为 Ohos 工程）。
3. 连接鸿蒙手机（开启开发者模式 / 无线调试或 USB 调试）或启动模拟器 → 点击 Run。
   - 首次运行需**签名**：DevEco 自动生成调试证书（File → Project Structure → Signing Configs → 勾选 Automatically generate）。
   - 路由表随功能调整变化，改完代码请** Rebuild HAP** 后再装回设备，避免页面跳转异常。
4. **权限说明**：首次使用会动态申请麦克风（开口自测录音）与通知（每日提醒）权限；振动权限已静态声明。
5. **每日提醒真机限制**：系统代理提醒在手机上有管控，三方应用默认需去华为 AppGallery Connect 申请「代理提醒开放能力」（效率 / 教育类通常可过，约 10 工作日审核）；**模拟器（API 20+）可直接调试**。ASR 端侧转写**仅真机支持**（模拟器无识别引擎）。

## 如何扩展内容（追加资料）

资料全部来自 `entry/src/main/resources/rawfile/data.json`。追加方式二选一：

**方式 A：改 markdown 后重跑脚本（推荐）**
1. 把新的逐字稿 / 专项 markdown 放进资料目录 `D:\Documents\口语练习`（脚本 `md2json.js` 的 `ROOT` 指向此处，即脚本读取源），或在该目录沿用现有文件追加内容。
2. 在 `md2json.js` 的 `questionFiles` / `articleFiles` / 套题解析区登记文件名与分组。
3. 运行：`node md2json.js` → 自动重新生成 `data.json`（覆盖）。重跑后记得 `git add` + commit（生成产物不会自动入库）。

**方式 B：直接编辑 data.json**
- 文章加一项到 `articles:[]`，字段：`id, title, category, tags[], summary, sections[{heading,body}]`
- 真题加一项到 `questions:[]`，字段：`id, source, type, typeCat, title, prompt, answerScript, tags[], thinkTime, speakTime, setId`
  - `thinkTime` / `speakTime`：思考 / 作答秒数（可选，套题模考分段计时用）
  - `setId`：归属套题 id（可选，不填则仅出现在「素材」真题列表）
- 套题加一项到 `sets:[]`，字段：`id, title, source, questionIds[], totalThink, totalSpeak`
- 若新增分类，同步更新 `tags.categories`。

## 文件结构

```
HebiInterviewApp/
├── md2json.js              # markdown→JSON 转换脚本（资料维护用）
├── gen_icon.js             # 占位图标生成脚本
├── AppScope/               # 应用级配置与图标
├── build-profile.json5     # ⚠️ 含签名 material，已 gitignore，勿入库
├── oh-package.json5
└── entry/
    └── src/main/
        ├── ets/
        │   ├── entryability/EntryAbility.ts
        │   ├── model/    (Types / DataStore / SearchEngine)
        │   ├── utils/
        │   │   ├── Theme.ets / BackHeader.ets / FavStore.ets / UserTagStore.ets
        │   │   ├── TtsManager.ets     # TTS 单例引擎（按句切分 + 续播）
        │   │   ├── TtsButton.ets      # 复用朗读按钮
        │   │   ├── TtsFloatButton.ets # 可拖拽悬浮播控条
        │   │   ├── RecorderBar.ets    # 开口自测录音条（AudioCapturer 直录 PCM→WAV）
        │   │   └── AsrHelper.ets      # 端侧语音转写封装（speechRecognizer）
        │   └── pages/
        │       ├── Index.ets          # 底部 4 Tab 容器（含通知直达路由）
        │       ├── Category.ets       # → CategoryView（嵌入 Index「素材」Tab）
        │       ├── Flashcard.ets      # → FlashcardView（嵌入「速记卡」Tab）
        │       ├── Practice.ets       # → PracticeView（嵌入「真题模考」Tab，含分段计时+振动）
        │       ├── Profile.ets        # → ProfileView（嵌入「个人中心」Tab）
        │       ├── StudyPlan.ets      # 备考计划（考试倒计时+复习清单+每日提醒+今日备考）
        │       ├── Search.ets         # 全文检索（支持 q 参数）
        │       ├── Detail.ets         # 知识点 / 真题详情（含 TTS 朗读 + 开口自测）
        │       ├── AudioAnswer.ets    # 音频作答：录音(实时波形) + AVPlayer 回放 + 本地模型点评
        │       ├── Favorites.ets      # 我的收藏（搜索 + 返回）
        │       ├── StudyRecord.ets    # 我的学习记录（搜索 + 返回）
        │       └── ExamRecord.ets     # 我的真题演练记录（搜索 + 返回）
        ├── resources/
        │   ├── base/   (string/color/profile/main_pages/media)
        │   ├── dark/   (深色模式 color)
        │   └── rawfile/data.json   # 全部结构化资料
        └── module.json5             # 权限声明（MICROPHONE / VIBRATE / PUBLISH_AGENT_REMINDER）
```

> 注：`Category / Flashcard / Practice / Profile` 已去掉 `@Entry`，改为可被 `Index` 的 `Tabs` 直接嵌入的 `View` 组件；`Search / Detail / Favorites / StudyRecord / ExamRecord / StudyPlan` 仍通过 `router` 独立路由跳转。

## 说明

- 本 APP 数据已内置结构化备考资料，覆盖考情、题型方法、主题专项等模块；具体篇目数随 `data.json` 更新变化。
- 真题模考对齐「先只给题、复盘才出逐字稿」的练习逻辑；套题含思考 / 作答分段计时与掌握度自评，结果沉淀到「个人中心 → 真题演练记录」。
- 语音播报按句切分实现暂停 / 续播；开口自测转写为纯端侧（零密钥、不上传），便于对照逐字稿自检口述差距。
- 每日备考提醒用系统代理提醒，内容由 App 打开后按当天日期动态生成（合规且避开后台刷新限制）；真机推送需先完成华为 AGC 的代理提醒开放能力申请。
- 代码按 HarmonyOS NEXT（API 20）写法；如你使用旧版 SDK，个别 import（如 `@kit.ArkData` 包路径）可能需按本地 SDK 微调。
- 仓库已配置 Gitee 远程（`git@gitee.com:maven27/hebi-interview-app.git`，SSH 免密）；日常改动走 `git add -A && git commit -m "..." && git push` 即可。

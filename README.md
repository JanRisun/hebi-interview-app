# 鹤壁事业编面试备考 · 鸿蒙 APP

一个**纯离线、无后端**的个人复习应用，把全部面试备考资料（总册、真题逐字稿、宣传类专项、考场贴士要点）结构化后装进手机。基于 HarmonyOS NEXT（Stage 模型，ArkTS + ArkUI），主打**底部 4 Tab 导航 + 真题套题模考 + 速记卡 + 个人学习档案**，随时随地复习。

## 功能

| 模块 | 说明 |
|------|------|
| **素材**（分类浏览） | 知识点按 考情 / 题型方法 / 专项练习 / 主题专项 / 宣传类专项 分组；真题按来源列出；顶部搜索框做全文检索 |
| **速记卡** | 百词斩式大卡片，点按翻转看要点；**左滑**下一题、**右滑**进入收藏 |
| **真题模考** | 四阶段流程：选题 → 模考 → 复盘 → 报告；支持 **32 套套题**与随机抽题；复盘前隐藏逐字稿，复盘时才展开参考答案 |
| **个人中心** | 三个入口：我的收藏、我的学习记录、我的真题演练记录（后两者为独立子页，均带**搜索 + 返回**） |
| 全文检索 | 关键词搜标题 / 正文 / 标签，按命中权重排序（Search 页支持 `q` 参数直达） |
| 我的收藏 | 基于 `@kit.ArkData` Preferences 持久化，重进不丢；支持搜索过滤 |

## 技术栈

- HarmonyOS NEXT（**Stage 模型**，API 12 写法；`UIAbility` + `WindowStage` + 声明式 ArkUI）
- 导航：`Tabs`（底部 4 Tab，`BarPosition.End`）+ `router.pushUrl`（子页用 `params` 对象传参，`router.back()` 返回）
- 数据：`resources/rawfile/data.json`（结构化 JSON，离线内置）
- 持久化：收藏 / 自评记录 / 模考记录 均用 `@kit.ArkData` Preferences
- 检索：纯前端本地全文匹配，无需联网

## 设计系统（Design Tokens + 深浅模式）

按 HarmonyOS Design「One Harmonious Universe」规范做了统一视觉升级，全部锁定 **API 12**，未引入 HarmonyOS 6 新能力（沉浸光感 / 悬浮页签等需 API 23，标记 `[需核实]`）。

- **颜色语义 Token**：集中在 `resources/base/element/color.json`（浅色）与 `resources/dark/element/color.json`（深色），键名一一对应，由资源系统随系统深浅**自动切换**；页面统一通过 `$r('app.color.*')` 引用，不再散落硬编码色值。主色沿用品牌蓝 `#185FA5`（深色模式提亮为 `#4A90D9`）。
- **字号 / 间距 / 圆角常量**：集中在 `entry/src/main/ets/utils/Theme.ets`（`FONT` / `SPACE` / `RADIUS`），全局复用，避免魔法数字。
  - 字号阶梯：display 20 / title 18 / body 16 / bodySm 14 / caption 12 / mini 11
  - 间距（4dp 基数）：xs 4 / sm 8 / md 12 / lg 16 / xl 24
  - 圆角：sm 8 / md 12 / lg 16 / pill 20 / xl 24
- **深色模式**：开箱即用——跟随系统设置，资源系统自动在 base↔dark 间切换；`EntryAbility` 另将当前 `colorMode` 同步进 `AppStorage` 供页面参考。
- **底部 Tab 图标**：由 emoji 替换为系统 **SymbolGlyph**（`sys.symbol.book` / `rectangle_stack` / `edit` / `person`），选中态高亮品牌色，矢量清晰、随字重缩放。

## 导入与运行（需在本地完成）

> 以下必须在你本地的 **DevEco Studio** 中完成。当前环境没有 DevEco / 鸿蒙 SDK / 签名证书，无法在此编译打包。

1. 安装 DevEco Studio（HarmonyOS NEXT 版本），配置 HarmonyOS SDK（API 12）。
2. 打开 DevEco Studio → Open → 选择本目录 `HebiInterviewApp`（识别为 Ohos 工程）。
3. 连接鸿蒙手机（开启开发者模式 / 无线调试或 USB 调试）或启动模拟器 → 点击 Run。
   - 首次运行需**签名**：DevEco 自动生成调试证书（File → Project Structure → Signing Configs → 勾选 Automatically generate）。
   - 路由表已随功能调整变化，改完代码请** Rebuild HAP** 后再装回设备，避免页面跳转异常。
   - 若图标报错，确认 `AppScope/resources/base/media/app_icon.png` 与 `entry/.../media/app_icon.png` 存在（本目录已用脚本生成占位图标，可替换）。

## 如何扩展内容（追加资料）

资料全部来自 `entry/src/main/resources/rawfile/data.json`。追加方式二选一：

**方式 A：改 markdown 后重跑脚本（推荐）**
1. 把新的逐字稿 / 专项 markdown 放进资料目录 `D:\Documents\口语练习`（脚本 `md2json.js` 的 `ROOT` 指向此处，即脚本读取源），或在该目录沿用现有文件追加内容。
2. 在 `md2json.js` 的 `questionFiles` / `articleFiles` / 套题解析区 登记文件名与分组。
3. 运行：`node md2json.js` → 自动重新生成 `data.json`（覆盖）。重跑后记得 `git add` + commit（生成产物不会自动入库）。

**方式 B：直接编辑 data.json**
- 文章加一项到 `articles:[]`，字段：`id, title, category, tags[], summary, sections[{heading,body}]`
- 真题加一项到 `questions:[]`，字段：`id, source, type, typeCat, title, prompt, answerScript, tags[], thinkTime, speakTime, setId`
  - `thinkTime` / `speakTime`：思考 / 作答秒数（可选，套题模考计时用）
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
        │   ├── utils/    (FavStore / BackHeader / Theme)
        │   └── pages/
        │       ├── Index.ets          # 底部 4 Tab 容器（素材/速记卡/模考/个人中心）
        │       ├── Category.ets       # → CategoryView（嵌入 Index「素材」Tab）
        │       ├── Flashcard.ets      # → FlashcardView（嵌入「速记卡」Tab）
        │       ├── Practice.ets       # → PracticeView（嵌入「真题模考」Tab）
        │       ├── Profile.ets        # → ProfileView（嵌入「个人中心」Tab）
        │       ├── Search.ets         # 全文检索（支持 q 参数）
        │       ├── Detail.ets         # 知识点 / 真题详情（逐字稿默认隐藏）
        │       ├── Favorites.ets      # 我的收藏（搜索 + 返回）
        │       ├── StudyRecord.ets    # 我的学习记录（搜索 + 返回）
        │       └── ExamRecord.ets     # 我的真题演练记录（搜索 + 返回）
        ├── resources/
        │   ├── base/   (string/color/profile/main_pages/media)
        │   └── rawfile/data.json   # 全部结构化资料（35 知识点 / 96 真题 / 32 套题）
        └── module.json5
```

> 注：`Category / Flashcard / Practice / Profile` 已去掉 `@Entry`，改为可被 `Index` 的 `Tabs` 直接嵌入的 `View` 组件；`Search / Detail / Favorites / StudyRecord / ExamRecord` 仍通过 `router` 独立路由跳转。

## 说明

- 本 APP 数据已内置 **35 篇知识点 + 96 道真题 + 32 套套题**（浚县不动产窗口岗备考方向），覆盖考情、六大题型方法、主题专项、宣传类专项。
- 真题模考对齐华图 / 粉笔式「先只给题、复盘才出逐字稿」的练习逻辑；套题含思考 / 作答计时与掌握度自评，结果沉淀到「个人中心 → 真题演练记录」。
- 考场一页纸贴士以「速记卡」模块（考情 + 题型方法要点）形式呈现；如需完整贴士原文，可在 `articles` 中补充对应条目。
- 代码按 HarmonyOS NEXT（API 12）写法；如你使用旧版 SDK，个别 import（如 `@kit.ArkData` vs `@ohos.data.preferences`）可能需按本地 SDK 微调。
- 仓库已配置 Gitee 远程（`git@gitee.com:maven27/hebi-interview-app.git`，SSH 免密）；日常改动走 `git add -A && git commit -m "..." && git push` 即可。

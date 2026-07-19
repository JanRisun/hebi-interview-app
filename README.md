# 鹤壁事业编面试备考 · 鸿蒙 APP

一个**纯离线、无后端**的个人复习应用，把全部面试备考资料（总册、5 套真题逐字稿、宣传类专项、考场贴士要点）结构化后装进手机，支持**全文检索、分类浏览、真题练习、收藏、随机抽题、速记卡**，随时随地复习。

## 功能

| 模块 | 说明 |
|------|------|
| 首页 | 六大入口导航 |
| 全文检索 | 关键词搜标题/正文/标签，按命中权重排序，附热门词快捷入口 |
| 分类浏览 | 知识点按 考情/题型方法/专项练习/主题专项/宣传类专项 分组；真题按来源列出 |
| 详情 | 知识点逐节展示；真题展示题目+逐字稿；可一键收藏 |
| 我的收藏 | 基于 Preferences 持久化，重进不丢 |
| 随机抽题 | 碎片时间口述自测，先看题、再对照逐字稿 |
| 速记卡 | 从"考情+题型方法"抽取核心要点，逐张翻看 |

## 技术栈

- HarmonyOS NEXT（Stage 模型，ArkTS + ArkUI）
- 数据：`resources/rawfile/data.json`（结构化 JSON，离线内置）
- 收藏：`@kit.ArkData` Preferences
- 检索：纯前端本地全文匹配，无需联网

## 导入与运行（需在本地完成）

> 以下三步必须在你本地的 **DevEco Studio** 中完成。当前环境没有 DevEco / 鸿蒙 SDK / 签名证书，无法在此编译打包。

1. 安装 DevEco Studio（HarmonyOS NEXT 版本），配置 HarmonyOS SDK（API 12）。
2. 打开 DevEco Studio → Open → 选择本目录 `HebiInterviewApp`（识别为 Ohos 工程）。
3. 连接鸿蒙手机（开启开发者模式/USB 调试）或启动模拟器 → 点击 Run。
   - 首次运行需**签名**：DevEco 会自动生成调试证书（File → Project Structure → Signing Configs → 勾选 Automatically generate）。
   - 若图标报错，确认 `AppScope/resources/base/media/app_icon.png` 与 `entry/.../media/app_icon.png` 存在（本目录已用脚本生成占位图标，可替换为你自己的）。

## 如何扩展内容（追加资料）

资料全部来自 `entry/src/main/resources/rawfile/data.json`。追加方式二选一：

**方式 A：改 markdown 后重跑脚本（推荐）**
1. 把新的逐字稿 / 专项 markdown 放进资料目录 `D:\Documents\口语练习`（脚本 `ROOT` 指向此处，即 `md2json.js` 读取源），或在该目录沿用现有文件追加内容。
2. 在 `md2json.js` 的 `questionFiles` / `articleFiles` 数组里登记文件名。
3. 运行：`node md2json.js` → 自动重新生成 `data.json`（覆盖）。

**方式 B：直接编辑 data.json**
- 文章加一项到 `articles:[]`，字段：`id, title, category, tags[], summary, sections[{heading,body}]`
- 真题加一项到 `questions:[]`，字段：`id, source, type, typeCat, title, prompt, answerScript, tags[]`
- 若新增分类，同步更新 `tags.categories`。

## 文件结构

```
HebiInterviewApp/
├── md2json.js              # markdown→JSON 转换脚本（资料维护用）
├── gen_icon.js             # 占位图标生成脚本
├── AppScope/               # 应用级配置与图标
├── build-profile.json5
├── oh-package.json5
└── entry/
    └── src/main/
        ├── ets/
        │   ├── entryability/EntryAbility.ts
        │   ├── model/  (Types / DataStore / SearchEngine)
        │   ├── utils/  (FavStore)
        │   └── pages/  (Index/Search/Category/Detail/Favorites/Practice/Flashcard)
        ├── resources/
        │   ├── base/   (string/color/profile/main_pages/media)
        │   └── rawfile/data.json   # 全部结构化资料
        └── module.json5
```

## 说明

- 本 APP 数据已内置 **29 篇知识点 + 15 道真题**（浚县 2025.6.21 + 真题一/二/三/四），覆盖考情、六大题型方法、九大主题专项、宣传类专项。
- 考场一页纸贴士以"速记卡"模块（考情+题型方法要点）形式呈现；如需完整贴士原文，可在 `articles` 中补充对应条目。
- 代码按 HarmonyOS NEXT（API 12）写法；如你使用旧版 SDK，个别 import（如 `@kit.ArkData` vs `@ohos.data.preferences`）可能需按本地 SDK 微调。

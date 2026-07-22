// 全局设计令牌（Design Tokens）
// 颜色见 resources/base|dark/element/color.json，通过 $r('app.color.xxx') 引用，深浅色自动切换
// 以下为深浅无关的字号 / 间距 / 圆角常量，集中复用，避免散落硬编码
//

// 安全区（状态栏 + 底部导航/手势区）适配参数：
// 各页根容器配合 expandSafeArea 使用 —— 背景延伸到系统条区域，内容自动避让，实现沉浸式效果
export const SAFE_AREA_TYPES: SafeAreaType[] = [SafeAreaType.SYSTEM];
export const SAFE_AREA_EDGES: SafeAreaEdge[] = [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM];

// 字号阶梯参考 HarmonyOS 文本排版规范（手机 vp）：
//   display 20 / title 18 / body 16 / bodySm 14 / caption 12 / mini 11
// 间距遵循 4dp 基数：xs4 / sm8 / md12 / lg16 / xl24
// 圆角：sm8 / md12 / lg16 / pill20（胶囊）/ xl24

interface FontTokens {
  display: number;
  title: number;
  body: number;
  bodySm: number;
  caption: number;
  mini: number;
}

interface SpaceTokens {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

interface RadiusTokens {
  sm: number;
  md: number;
  lg: number;
  pill: number;
  xl: number;
}

export const FONT: FontTokens = {
  display: 20,
  title: 18,
  body: 16,
  bodySm: 14,
  caption: 12,
  mini: 11
};

export const SPACE: SpaceTokens = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24
};

export const RADIUS: RadiusTokens = {
  sm: 8,
  md: 12,
  lg: 16,
  pill: 20,
  xl: 24
};

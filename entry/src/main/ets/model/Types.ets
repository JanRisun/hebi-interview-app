// 数据结构定义（与 rawfile/data.json 对应）
export interface Section {
  heading: string;
  body: string;
}

export interface Article {
  id: string;
  title: string;
  category: string;
  tags: string[];
  summary: string;
  sections: Section[];
  fav?: boolean;
}

export interface Question {
  id: string;
  source: string;
  type: string;
  typeCat: string;
  title: string;
  prompt: string;
  answerScript: string;
  thinkTime?: number;   // 建议思考时长（秒），新格式从「**思考时间：**」解析
  speakTime?: number;   // 建议作答时长（秒），新格式从「**作答时间：**」解析
  setId?: string;        // 所属套题 id（真题模考用）
  tags: string[];
  fav?: boolean;
}

// 套题（真题模考单元）：一套通常为 3 题，含建议总时长
export interface MockSet {
  id: string;
  title: string;
  source: string;
  questionIds: string[];
  totalThink: number;   // 本套建议思考总时长（秒），0 表示无
  totalSpeak: number;   // 本套建议作答总时长（秒），0 表示无
}

export interface Tags {
  categories: string[];
  keywords: string[];
}

// 答题记录（音频作答）：记录思考时长与作答时长
export interface AnswerRecord {
  id: string;          // 题目 id
  title: string;      // 题目标题
  thinkSec: number;   // 思考了多久（秒）
  speakSec: number;   // 回答了多久（秒）
  date: string;       // 作答完成时间 YYYY-MM-DD HH:mm
  audioPath: string;  // 录音文件绝对路径
}

export interface AppData {
  meta: object;
  articles: Article[];
  questions: Question[];
  sets: MockSet[];
  tags: Tags;
}

export interface SearchHit {
  kind: 'article' | 'question';
  id: string;
  title: string;
  category: string;
  score: number;
}

// 个人中心-我的学习记录（自评索引，本地 prefs 读取）
export interface RatedItem {
  id: string;       // 题目 id
  title: string;    // 题目标题（查 DataStore）
  rating: string;   // 掌握 / 模糊 / 不会
}

// 个人中心-我的真题演练记录（每完成一套模考写一条，本地 prefs 读取）
export interface PracticeSession {
  setTitle: string;   // 套题标题
  date: string;       // 完成时间（YYYY-MM-DD HH:mm）
  durationSec: number; // 用时（秒）
  master: number;     // 掌握数
  vague: number;      // 模糊数
  fail: number;       // 不会数
}

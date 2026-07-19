import { AppData, SearchHit } from './Types';

// 本地全文检索：标题 / 标签 / 小节标题 / 正文 加权匹配，按得分降序
export function searchAll(data: AppData, kw: string): SearchHit[] {
  const q: string = (kw || '').trim().toLowerCase();
  if (!q) {
    return [];
  }
  const res: SearchHit[] = [];

  data.articles.forEach((a) => {
    let score = 0;
    if (a.title.toLowerCase().includes(q)) {
      score += 10;
    }
    a.tags.forEach((t) => {
      if (t.toLowerCase().includes(q)) {
        score += 5;
      }
    });
    a.sections.forEach((s) => {
      if (s.heading.toLowerCase().includes(q)) {
        score += 2;
      }
      if (s.body.toLowerCase().includes(q)) {
        score += 3;
      }
    });
    if (score > 0) {
      res.push({ kind: 'article', id: a.id, title: a.title, category: a.category, score });
    }
  });

  data.questions.forEach((qq) => {
    let score = 0;
    if (qq.title.toLowerCase().includes(q)) {
      score += 10;
    }
    qq.tags.forEach((t) => {
      if (t.toLowerCase().includes(q)) {
        score += 5;
      }
    });
    if (qq.prompt.toLowerCase().includes(q)) {
      score += 3;
    }
    if (qq.answerScript.toLowerCase().includes(q)) {
      score += 3;
    }
    if (score > 0) {
      res.push({ kind: 'question', id: qq.id, title: qq.title, category: qq.source, score });
    }
  });

  return res.sort((a, b) => b.score - a.score);
}

// 生成命中片段（用于列表预览）
export function snippet(text: string, kw: string, len: number = 50): string {
  const idx: number = text.toLowerCase().indexOf((kw || '').toLowerCase());
  if (idx < 0) {
    return text.slice(0, len);
  }
  const s: number = Math.max(0, idx - 15);
  return (s > 0 ? '…' : '') + text.slice(s, s + len) + '…';
}

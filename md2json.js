// 把备考 markdown 批量转换为鸿蒙 App 用的结构化 JSON
// 用法: node md2json.js
const fs = require('fs');
const path = require('path');

const ROOT = 'D:/Documents/口语练习';
const SRC = ROOT;
const OUT = path.join(__dirname, 'entry/src/main/resources/rawfile');
fs.mkdirSync(OUT, { recursive: true });
const NL = String.fromCharCode(10);

/* ---------- 工具：markdown -> 纯文本 ---------- */
function stripMd(t) {
  return t
    .replace(/^\s*\|[-: |]+\|\s*$/gm, '')          // 表格分隔行
    .replace(/^\s*[\*\-]\s+/gm, '• ')              // 列表符号
    .replace(/\*\*(.+?)\*\*/g, '$1')               // 加粗
    .replace(/`(.+?)`/g, '$1')                     // 行内代码
    .replace(/^>\s?/gm, '')                         // 引用
    .replace(/^#+\s+/gm, '')                        // 残留标题
    .replace(/\|/g, ' / ')                          // 表格竖线
    .split('\n')
    .map(l => l.trim())
    .filter((l, i, a) => !(l === '' && a[i - 1] === ''))
    .join('\n')
    .trim();
}

/* ---------- 工具：题型归类 ---------- */
function catOf(type) {
  if (/演讲/.test(type)) return '演讲';
  if (/综合分析/.test(type)) return '综合分析';
  if (/人际/.test(type)) return '人际关系';
  if (/应急/.test(type)) return '应急应变';
  if (/情景|模拟/.test(type)) return '情景模拟';
  if (/岗位认知/.test(type)) return '岗位认知';
  if (/组织管理|调研/.test(type)) return '组织管理';
  return '其他';
}

/* ---------- 工具：关键词标签 ---------- */
const KW = ['综合分析','组织管理','人际关系','应急应变','应急处突','安全生产',
  '情景模拟','演讲','岗位认知','乡村振兴','基层治理','一老一小','民生服务',
  '作风建设','工作制度','营商环境','青年干部','政务服务','宣传类','调研',
  '窗口服务','浚县','鹤壁','河南','真题','逐字稿'];
function kwOf(text) {
  return KW.filter(k => text.includes(k));
}

/* ---------- 解析逐字稿 -> questions（兼容两种模板） ---------- */
function parseQuestions(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const lines = raw.split('\n');
  const srcShort = srcName(path.basename(file));
  const blocks = [];
  let cur = null, curHeading = '';
  const blkStart = /^#{1,4}\s*第\s*[一二三四五六七八九十\d]+\s*题/;
  const setStart = /^###\s*套题\s*[一二三四五六七八九十\d]*/;   // 套题标记（H3）：套题 1 / 套题演练 一
  const sets = [];                 // 本文件发现的套题（有序、去重）
  let setSeen = false;             // 本文件是否含显式套题标记
  let curSetId = '';
  let curSetTitle = '';
  let setCounter = 0;
  let curPart = '';                // 上级「## …部分」标题，作为套题显示前缀
  for (const line of lines) {
    const sm = line.match(setStart);
    if (sm) {                      // 遇到套题标记：先收尾上一题块，再开新套
      if (cur) { blocks.push({ heading: curHeading, lines: cur, setId: curSetId }); cur = null; }
      setSeen = true;
      setCounter++;
      curSetId = 'set_' + srcCode(srcShort) + '_' + setCounter;
      curSetTitle = (curPart ? curPart + ' · ' : '') + line.replace(/^#+\s*/, '').trim();
      sets.push({ id: curSetId, title: curSetTitle, source: srcShort });
      continue;
    }
    const h2 = line.match(/^##\s+(.+?)\s*$/);
    if (h2 && /部分/.test(h2[1])) { curPart = h2[1].replace(/（.*$/, '').trim(); continue; }
    const m = line.match(blkStart);
    if (m) {
      if (!setSeen && !curSetId) {   // 无显式套题标记的文件：整份=1套
        setCounter++;
        curSetId = 'set_' + srcCode(srcShort) + '_file';
        curSetTitle = srcShort + '（真题/模拟）';
        sets.push({ id: curSetId, title: curSetTitle, source: srcShort });
      }
      if (cur) blocks.push({ heading: curHeading, lines: cur, setId: curSetId });
      curHeading = line.replace(/^#+\s*/, '').trim();
      cur = [];
    } else if (cur) {
      cur.push(line);
    }
  }
  if (cur) blocks.push({ heading: curHeading, lines: cur, setId: curSetId });

  const qs = blocks.map((b, i) => {
    // 题块内的小节（## 或 ###）
    const secs = [];
    let s = null;
    for (const line of b.lines) {
      const sm = line.match(/^#{2,3}\s+(.+?)\s*$/);
      if (sm) { if (s) secs.push(s); s = { heading: sm[1].trim(), lines: [] }; }
      else if (s) s.lines.push(line);
    }
    if (s) secs.push(s);
    const secMap = {};
    secs.forEach(x => { secMap[x.heading] = x.lines.join('\n'); });

    // prompt = 题目回顾 / 题目信息 / 题目（去掉 题型、作答时长 两行元数据）
    const promptRaw = Object.entries(secMap)
      .filter(([k]) => /题目/.test(k))
      .map(([, v]) => v).join('\n');
    let prompt;
    if (promptRaw.trim()) {
      prompt = stripMd(promptRaw)
        .split(NL)
        .filter(l => !l.startsWith('**题型') && !l.startsWith('**作答时长'))
        .join(NL);
    } else {
      const j = b.lines.findIndex(l => l.includes('**题目'));
      if (j >= 0) {
        const p2 = [];
        let same = b.lines[j];
        const ci = same.indexOf('：');
        if (ci >= 0) same = same.slice(ci + 1);
        while (same.startsWith('*') || same.startsWith(' ')) same = same.slice(1);
        same = same.trim();
        if (same) p2.push(same);
        for (let k = j + 1; k < b.lines.length; k++) {
          const l = b.lines[k];
          if (l.startsWith('**思考时间') || l.startsWith('**作答时间') || l.startsWith('>')) break;
          p2.push(l);
        }
        prompt = stripMd(p2.join(NL));
      } else prompt = '';
    }
    // answerScript：旧格式取「除题目/复盘外的小节」；新格式取 思考/作答时间 后的正文（去掉 ★贴靠 引用）
    const ansSecs = secs.filter(x => !/题目/.test(x.heading) && !/作答复盘表/.test(x.heading));
    let answerScript;
    if (ansSecs.length) {
      answerScript = stripMd(ansSecs.map(x =>
        (x.heading ? '【' + x.heading.replace(/【|】/g, '') + '】\n' : '') + x.lines.join('\n')
      ).join('\n\n'));
    } else {
      const t = b.lines.findIndex(l => /^\s*\*\*作答时间|^\s*\*\*思考时间/.test(l));
      if (t >= 0) {
        const a = [];
        for (let k = t + 1; k < b.lines.length; k++) {
          const l = b.lines[k];
          if (/^\s*>/.test(l)) break;
          a.push(l);
        }
        answerScript = stripMd(a.join('\n'));
      } else answerScript = '';
    }

    const full = b.lines.join('\n');
    let typeM = full.match(/\*\*题型[定位于]*\*\*[：:]\s*(.+)/);
    if (!typeM) {
      const hm2 = b.heading.match(/[｜|]\s*(.+?)\s*$/);   // 新格式：第X题 ｜ 类型
      if (hm2) typeM = { 1: hm2[1] };
    }
    if (!typeM) typeM = b.heading.match(/[（(](.+?)[)）]/);  // 浚县式：标题括号内
    const type = typeM ? typeM[1].trim().split('\n')[0] : '';

    // 标题
    let title;
    const hm = b.heading.match(/第\s*[一二三四五六七八九十\d]+题\s*[：:]\s*(.+)/);
    if (hm) title = hm[1].trim();
    else if (/逐字稿$/.test(b.heading)) {
      const fs2 = prompt.split(/[。？?]/)[0] || '';
      title = b.heading.replace(/\s*逐字稿$/, '') + '：' + fs2.slice(0, 22);
    } else {
      // 新格式：第 X 题 ｜ 类型 → 用「类型：题目首句」
      const fs2 = prompt.split(/[。？?]/)[0] || '';
      const cat2 = b.heading.replace(/^第\s*[一二三四五六七八九十\d]+\s*题/, '').replace(/^[｜|\s]+/, '') || '题';
      title = fs2 ? (cat2 + '：' + fs2.slice(0, 22)) : cat2;
    }

    // 思考/作答时长（新格式单行：『**思考时间：** 约 30 秒 ｜ **作答时间：** 约 2 分 30 秒』）
    let thinkTime, speakTime;
    const durLine = b.lines.find(l => /^\s*\*\*思考时间/.test(l));
    if (durLine) {
      const parts = durLine.split('｜');
      thinkTime = parseDur(parts[0]);
      speakTime = parts.length > 1 ? parseDur(parts[1]) : undefined;
    }

    const tags = Array.from(new Set([catOf(type), srcShort, ...kwOf(title + answerScript)]));
    return {
      id: 'q_' + srcCode(srcShort) + '_' + (i + 1),
      source: srcShort,
      type: type,
      typeCat: catOf(type),
      title: title,
      prompt: prompt,
      answerScript: answerScript,
      thinkTime: thinkTime,
      speakTime: speakTime,
      tags: tags,
      setId: b.setId,
      fav: false
    };
  });
  return { questions: qs, sets };
}

// 解析"约 30 秒" / "约 2 分 30 秒" -> 秒数
function parseDur(t) {
  if (!t) return undefined;
  let s = 0;
  const mF = t.match(/(\d+)\s*分/);
  const mS = t.match(/(\d+)\s*秒/);
  if (mF) s += parseInt(mF[1], 10) * 60;
  if (mS) s += parseInt(mS[1], 10);
  return s > 0 ? s : undefined;
}

function srcName(fn) {
  if (/浚县/.test(fn)) return '浚县2025.6.21';
  if (/真题一/.test(fn)) return '真题一';
  if (/真题二/.test(fn)) return '真题二';
  if (/真题三/.test(fn)) return '真题三';
  if (/真题四/.test(fn)) return '真题四';
  if (/终期四|期末四/.test(fn)) return '终期模拟四';
  if (/模拟题/.test(fn)) return '模拟题';
  return fn;
}
// 来源 -> 短代码（用于生成规整且唯一的 id）
function srcCode(s) {
  const m = {
    '浚县2025.6.21': 'junxian',
    '真题一': 't1', '真题二': 't2', '真题三': 't3', '真题四': 't4',
    '终期模拟四': 'm4',
    '模拟题': 'mock'
  };
  return m[s] || slug(s) || 'x';
}
function slug(s) { return s.replace(/[^a-zA-Z0-9]/g, ''); }

/* ---------- 解析总册/专项 -> articles ---------- */
function parseArticles(file, fileCat) {
  const raw = fs.readFileSync(file, 'utf8');
  const lines = raw.split('\n');
  const out = [];
  let curH1 = '';
  let art = null;
  let sec = null;
  const flushSec = () => { if (art && sec) { art.sections.push(sec); sec = null; } };
  const flushArt = () => { flushSec(); if (art) out.push(art); art = null; };
  const mapH1 = (h) => {
    if (/第一篇/.test(h)) return '题型方法';
    if (/第二篇/.test(h)) return '专项练习';
    if (/第三篇/.test(h)) return '主题专项';
    return fileCat || '其他';
  };

  for (const line of lines) {
    const h1 = line.match(/^#\s+(.+?)\s*$/);
    const h2 = line.match(/^##\s+(.+?)\s*$/);
    const h3 = line.match(/^###\s+(.+?)\s*$/);
    if (h1) {
      flushArt();
      curH1 = h1[1];
      // 文档标题（含"备考总册"）下紧跟的 h2 视为考情
      if (/备考总册/.test(curH1)) curH1 = '__title__';
    } else if (h2) {
      flushArt();
      let cat;
      if (curH1 === '__title__') cat = /考情/.test(h2[1]) ? '考情' : fileCat;
      else cat = mapH1(curH1);
      art = { title: h2[1].trim(), category: cat, tags: [], sections: [] };
      sec = { heading: '', body: '' };   // h2 下无 h3 时，整段作为首小节
    } else if (h3 && art) {
      flushSec();
      sec = { heading: h3[1].trim(), body: '' };
    } else if (sec) {
      sec.body += line + '\n';
    }
  }
  flushArt();

  return out
    .filter(a => a.sections.length > 0)
    .map((a, i) => {
      const sections = a.sections
        .map(s => ({ heading: s.heading, body: stripMd(s.body) }))
        .filter(s => s.body.trim().length > 0);
      const full = a.title + sections.map(s => s.heading + s.body).join(' ');
      const tags = Array.from(new Set([a.category, ...kwOf(full)]));
      return {
        id: 'a_' + slug(a.category) + '_' + (i + 1),
        title: a.title,
        category: a.category,
        tags: tags,
        summary: sections[0] ? sections[0].body.slice(0, 60) : '',
        sections: sections,
        fav: false
      };
    });
}

/* ---------- 主流程 ---------- */
const questionFiles = [
  '04-真题模拟/2025年6月21日浚县事业编面试真题逐字稿.md',
  '04-真题模拟/事业单位面试真题一逐字稿.md',
  '04-真题模拟/事业单位面试真题二逐字稿.md',
  '04-真题模拟/事业单位面试真题三逐字稿.md',
  '04-真题模拟/事业单位面试真题四逐字稿.md',
  '04-真题模拟/事业单位面试模拟题逐字稿.md',
  '04-真题模拟/事业单位面试模拟题_终期四逐字稿.md',
  '02-逐字稿/套题训练20260809_逐字稿.md'
];
const articleFiles = [
  { f: '00-备考总册/鹤壁事业编综合类面试备考总册.md', cat: '主题专项' },
  { f: '01-专项拆解/鹤壁事业编宣传类题型专项拆解.md', cat: '宣传类专项' },
  { f: '07-IMA知识库整理/知识库总索引与窗口岗优先清单.md', cat: '索引' }
];

let questions = [];
let setsRaw = [];
questionFiles.forEach(f => {
  const p = path.join(SRC, f);
  if (fs.existsSync(p)) {
    const r = parseQuestions(p);
    questions = questions.concat(r.questions);
    setsRaw = setsRaw.concat(r.sets);
  }
});

// 套题装配：补齐 questionIds 与建议总时长
const qBySet = {};
questions.forEach(q => { (qBySet[q.setId] || (qBySet[q.setId] = [])).push(q); });
const seenSet = new Set();
const sets = [];
setsRaw.forEach(s => {
  if (seenSet.has(s.id)) return;
  seenSet.add(s.id);
  const qs = qBySet[s.id] || [];
  const totalThink = qs.reduce((a, q) => a + (q.thinkTime || 0), 0);
  const totalSpeak = qs.reduce((a, q) => a + (q.speakTime || 0), 0);
  sets.push({
    id: s.id,
    title: s.title,
    source: s.source,
    questionIds: qs.map(q => q.id),
    totalThink,
    totalSpeak
  });
});

let articles = [];
articleFiles.forEach(({ f, cat }) => {
  const p = path.join(SRC, f);
  if (fs.existsSync(p)) articles = articles.concat(parseArticles(p, cat));
});

// 统计分类
const categories = Array.from(new Set(articles.map(a => a.category)));
const keywordSet = new Set();
articles.concat(questions).forEach(o => o.tags.forEach(t => keywordSet.add(t)));

const data = {
  meta: { generated: new Date().toISOString().slice(0, 10), articles: articles.length, questions: questions.length, sets: sets.length },
  articles: articles,
  questions: questions,
  sets: sets,
  tags: { categories: categories, keywords: Array.from(keywordSet) }
};

fs.writeFileSync(path.join(OUT, 'data.json'), JSON.stringify(data, null, 2), 'utf8');
console.log('articles:', articles.length, '| questions:', questions.length);
console.log('categories:', categories.join(', '));
console.log('written ->', path.join(OUT, 'data.json'));

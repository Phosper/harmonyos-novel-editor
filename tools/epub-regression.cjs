// Node 24+. EPUB 解析的纯逻辑：container → OPF → spine → 章节文本。
// 解压与读文件不在这一步（由 EpubImporter 在设备上做），所以这里能把"书长什么样"钉死。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/EpubParser.ets'), 'utf8');
const compiled = stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace(/\bexport\s+/g, ''), { mode: 'transform' });
const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
vm.runInContext(compiled, context);
const api = vm.runInContext('({ parseEpub, epubHtmlToText, epubDecodeEntities, epubResolvePath, epubTocTitles })', context);

let pass = 0;
function check(name, action) {
  action();
  pass++;
  console.log('PASS ' + name);
}

const container = `<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>`;

// manifest 顺序故意与 spine 相反：章节顺序必须听 spine 的
const opf = `<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>国际关系理论</dc:title>
    <dc:creator>某作者</dc:creator>
  </metadata>
  <manifest>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="style" href="style.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>`;

const ch1 = `<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>封面</title>
<style>.x{color:red}</style></head>
<body><h1>第一章 现实主义</h1>
<p>古典现实主义强调&nbsp;人性&amp;权力。</p>
<script>var a = 1;</script>
<p>第二段<br/>换行后</p>
</body></html>`;

const ch2 = `<html><body><h2>第二章 新现实主义</h2><p>结构压力：&#8220;体系&#8221;决定行为。</p></body></html>`;

// Calibre 常见的书：正文没有 h1，章节名只在 toc.ncx 里
const ncx = `<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1" playOrder="1"><navLabel><text>封面</text></navLabel><content src="text/ch1.xhtml"/></navPoint>
    <navPoint id="n2" playOrder="2"><navLabel><text>第一章 软实力</text></navLabel><content src="text/ch2.xhtml"/>
      <navPoint id="n3" playOrder="3"><navLabel><text>何谓实力</text></navLabel><content src="text/ch2.xhtml#sec2"/></navPoint>
    </navPoint>
  </navMap>
</ncx>`;

const files = () => [
  { path: 'META-INF/container.xml', text: container },
  { path: 'OEBPS/content.opf', text: opf },
  { path: 'OEBPS/text/ch1.xhtml', text: ch1 },
  { path: 'OEBPS/text/ch2.xhtml', text: ch2 }
];

check('spine 决定章节顺序，书名/作者取自 OPF', () => {
  const book = api.parseEpub(files());
  assert.equal(book.title, '国际关系理论');
  assert.equal(book.author, '某作者');
  assert.deepEqual(JSON.parse(JSON.stringify(book.chapters.map(c => c.title))),
    ['第一章 现实主义', '第二章 新现实主义']);
});

check('正文只留文字：实体解码、脚本与样式被丢弃、段落保留换行', () => {
  const book = api.parseEpub(files());
  const first = book.chapters[0].content;
  assert.ok(first.startsWith('第一章 现实主义'), 'heading stays as text');
  assert.ok(first.includes('古典现实主义强调 人性&权力。'), 'nbsp/amp decoded');
  assert.ok(!first.includes('var a'), 'script removed');
  assert.ok(!first.includes('color:red'), 'style removed');
  assert.ok(first.includes('\n换行后'), 'br becomes a line break');
  const second = book.chapters[1].content;
  assert.ok(second.includes('“体系”'), 'numeric entities decoded');
});

check('缺少 container 时按 html 文件顺序兜底', () => {
  const book = api.parseEpub([
    { path: 'a/2.xhtml', text: '<html><body><p>二</p></body></html>' },
    { path: 'a/1.xhtml', text: '<html><body><p>一</p></body></html>' }
  ]);
  assert.equal(book.chapters.length, 2);
  assert.equal(book.chapters[0].content, '一');
  assert.equal(book.chapters[0].title, '第 1 部分');
});

check('相对路径与 URL 编码', () => {
  assert.equal(api.epubResolvePath('OEBPS', 'text/ch1.xhtml'), 'OEBPS/text/ch1.xhtml');
  assert.equal(api.epubResolvePath('OEBPS/text', '../images/../text/a%20b.xhtml'), 'OEBPS/text/a b.xhtml');
  assert.equal(api.epubResolvePath('OEBPS', '/abs/ch1.xhtml#p3'), 'abs/ch1.xhtml');
});

check('空包或没有正文时返回 undefined，不抛错', () => {
  assert.equal(api.parseEpub([]), undefined);
  assert.equal(api.parseEpub([{ path: 'META-INF/container.xml', text: container }]), undefined);
});

check('toc.ncx 提供章节名：同名文件只取第一条，锚点被忽略', () => {
  const titles = api.epubTocTitles(ncx, 'toc.ncx');
  assert.equal(titles.get('text/ch1.xhtml'), '封面');
  assert.equal(titles.get('text/ch2.xhtml'), '第一章 软实力', 'nested nav point must not override the parent');
  // 同一文件的不同锚点归一成同一路径，不会产生重复章节
  assert.equal(titles.get('text/ch2.xhtml#sec2'), undefined);
  const book = api.parseEpub([
    { path: 'META-INF/container.xml', text: container },
    { path: 'OEBPS/content.opf', text: opf },
    { path: 'toc.ncx', text: ncx },
    { path: 'OEBPS/text/ch1.xhtml', text: '<html><body><p>封面文字</p></body></html>' },
    { path: 'OEBPS/text/ch2.xhtml', text: '<html><body><p>正文</p></body></html>' }
  ]);
  // NCX 路径（text/...）与包内实际路径（OEBPS/text/...）不一致时退回标题标签/兜底，
  // 不会把别的章节名硬套上去
  assert.equal(book.chapters.length, 2);
  assert.deepEqual(JSON.parse(JSON.stringify(book.chapters.map(c => c.title))), ['第 1 部分', '第 2 部分']);
});

check('目录名优先生效（路径一致时）', () => {
  const book = api.parseEpub([
    { path: 'META-INF/container.xml', text: container },
    { path: 'OEBPS/content.opf', text: opf },
    { path: 'OEBPS/toc.ncx', text: ncx },
    { path: 'OEBPS/text/ch1.xhtml', text: '<html><body><p>封面文字</p></body></html>' },
    { path: 'OEBPS/text/ch2.xhtml', text: '<html><body><p>正文</p></body></html>' }
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(book.chapters.map(c => c.title))),
    ['封面', '第一章 软实力'], 'toc titles win over "第 N 部分"');
});

console.log('EPUB regression: ' + pass + ' checks passed');

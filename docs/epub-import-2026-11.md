# EPUB 导入（2026-11）

- 状态：**代码完成、纯逻辑已回归；解压与真机未验证**（本机看不到设备）
- 范围（按计划 `p7-epub`）：按章拆分文稿、保留书名/作者/目录顺序；**图片与版式降级为纯文本并明确提示**

## 1. 怎么做

```
文件选择器（.epub）
  → 复制到缓存目录（选择器给的是内容 URI，zlib 只认路径）
  → zlib.decompressFile 解压到临时目录
  → 读 META-INF/container.xml → 找到 OPF
  → 读 OPF：书名/作者 + manifest(href) + spine(阅读顺序)
  → 只读 spine 指向的 xhtml（不遍历整包，大书不把图片读进内存）
  → 纯解析器：XHTML → 纯文本；每个 spine 项 = 一篇文稿
  → 建文稿（TXT）+ 写入正文；单章超限只跳过该章
  → 清理临时目录
```

| 层 | 文件 | 说明 |
| --- | --- | --- |
| 纯解析（无 IO） | [EpubParser.ets](../entry/src/main/ets/utils/EpubParser.ets) | `container → OPF → spine → 章节`；实体解码、去 script/style、`<br>` 与块级标签转换行；路径解析支持 `../` 与 URL 编码 |
| 设备侧 | [EpubImporter.ets](../entry/src/main/ets/utils/EpubImporter.ets) | 复制、解压、按需读取、清理；失败返回 `undefined` 不抛给 UI |
| 分类与选择 | [ImportService.ets](../entry/src/main/ets/utils/ImportService.ets) | 新增 `ImportKind.EPUB`，后缀过滤加 `.epub`；**EPUB 不做 UTF-8 解码**（二进制） |
| 入库 | [AppStores.ets](../entry/src/main/ets/store/AppStores.ets) | 每章一篇文稿；汇总里明确写「EPUB 仅保留文字，图片与版式未导入」 |

## 2. 明确保留的语义

- **顺序**听 OPF 的 `spine`，不听文件名、也不听 manifest 顺序（回归里故意把两者写反）。
- 章节标题取该章第一个 `h1–h3`；没有就写「第 N 部分」。
- 书名/作者取 `dc:title` / `dc:creator`；书名缺失时退回第一章标题。
- 缺少 container / OPF 时，退化为"按 xhtml 文件名顺序"导入，不整本失败。
- spine 引用了不存在的文件：跳过该章并记日志。
- 单章超过入库上限：跳过该章，其余照常导入（与 txt/md 一致）。

## 3. 验证

| 项 | 结果 |
| --- | --- |
| `tools/epub-regression.cjs` | **5 项**：spine 顺序、书名作者、实体解码、脚本/样式剔除、缺少 container 兜底、路径解析、空包 |
| `tools/import-regression.cjs` | 7 → **8 项**：`.epub` 分类且不按文本解码 |
| 构建 | 0 ERROR / **111 WARN**（新增 6 条均为 `Function may throw`，来自 fileIo/zlib 调用，已在 try/catch 内） |
| 回归合计 | 391 → **397 项** |

## 4. 未测（必须有设备）

1. `zlib.decompressFile` 对真实 EPUB（含 `mimetype` 存储、非 ASCII 路径）的表现；
2. 大文件（>50MB）解压耗时与内存；
3. 中文 EPUB（竖排、注释、脚注链接）转纯文本的观感；
4. 导入后文稿顺序与目录是否与阅读器一致。

## 5. 已知限制（有意为之）

- 不解析内嵌字体/样式，正文统一按纯文本进 TXT（与"图片与版式降级"一致）；
- 不读目录（toc.ncx / nav.xhtml）里的层级，只按 spine 一项一篇；若某书把多章塞进一个 xhtml，会变成一篇；
- 不保留图片（后续若要做，需要附件体系，属于 P7 的 `Attachment`）。

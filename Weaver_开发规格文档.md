# 鸿蒙全场景小说创作平台 — 开发规格文档

## 项目概述

- 名称：鸿蒙全场景小说创作平台
- 类型：HarmonyOS 原生应用（ArkTS + ArkUI）
- 目标SDK：HarmonyOS 7 (API 26)
- 设备：手机 / 平板 / PC / 二合一设备（一多适配）
- 赛题方向：应用创新

---

## 一、架构概览

```
冷启动 → Splash（系统启动页）
   → 标准化隐私弹窗（系统托管，首次安装自动弹出）
       └→ 用户点"同意"
           ├─ 首次启动 → 引导页（3 页）→ 模式选择 → 编辑器
           └─ 非首次   → 编辑器（上次退出位置）
```

### 模式说明

- 模式：Tab结构；用户画像
- 普通：编辑、我的；日常写作用户，无小说创作需求
- 专业：编辑、素材、关系、我的；长篇创作者，需要人物/世界观/关系图管理

切换方式：「我的」Tab → 模式切换。首次打开在引导页选择，不做设备预选。

---

## 二、页面清单与跳转关系

### 2.1 页面树

```
引导页（首次启动，3 页轮播）
  ├── 第 1 页：品牌认知
  ├── 第 2 页：功能预览
  └── 第 3 页：模式选择 → 点击卡片进入编辑器
       ├── 侧滑栏（书籍/章节管理）
       ├── 顶部 ← 返回 → 项目工作台（仅专业模式）
       ├── Agent 半屏（可唤起）
       ├→ 人物详情页
       ├→ 世界设定详情页
       ├→ 关系图全屏页
       ├→ 灵感创建页（FAB触发）
       └→ 设定创建页（人物/世界观）

素材 Tab（专业模式）
  ├── 设定子Tab → 人物卡片列表 + 世界观卡片列表
  └── 灵感子Tab → 本书灵感（上）/ 全部灵感（下）

关系 Tab（专业模式）
  └── 当前书人物关系可视化图

我的 Tab
  ├── 模式切换
  ├── 稿纸/背景主题
  ├── 隐私防窥开关
  └── 关于
```

### 2.2 侧滑栏结构（编辑页左上角 ☰）

```
┌──────────────────┐
│ 当前书籍：《书名》  │
├──────────────────┤
│ ○ 第1章          │  ← 点击切换到该章节
│ ○ 第2章          │
│ ○ 第3章（当前）   │  ← 高亮
│ …                │
├──────────────────┤
│ [+ 新建章节]      │
│ [+ 切换书籍]      │
│ [+ 新建书籍]      │
└──────────────────┘
```

---

## 三、Tab 结构

### 3.1 普通模式

- Tab：图标；内容
- 编辑：✏️ 笔图标；编辑器（上次退出位置）
- 我的：👤 人物图标；设置 / 模式切换 / 稿纸 / 隐私

### 3.2 专业模式

- Tab：图标；内容
- 编辑：✏️ 笔图标；编辑器 + 当前已打开书籍的章节列表（侧滑栏）
- 素材：📦 箱图标；子Tab [设定] [灵感]
- 关系：🕸 网图标；人物关系可视化图
- 我的：👤 人图标；设置 / 模式切换 / 稿纸 / 隐私

---

## 四、页面详细设计

### 4.1 编辑器页面

**布局**：
```
┌──────────────────────────────┐
│  ← ☰      章节名       🤖    │  ← 顶栏（←返回项目工作台，☰侧滑栏，🤖Agent入口）
├──────────────────────────────┤
│                              │
│         写作区域              │  ← 纯文本 / Markdown
│     （上次光标位置）           │
│                              │
├──────────────────────────────┤
│  B  I  图片  链接  ···       │  ← 工具栏（4按钮）
└──────────────────────────────┘
     ┌───┐
     │ + │  ← FAB（新建章节）右下角
     └───┘
```

**FAB 行为**：
- 键盘弹起 → FAB 收起（0.2s 缩放动画）
- 向下滑动（翻页阅读）→ FAB 收起
- 向上滑动（回翻）→ FAB 展开
- 智感握姿 → 左手时靠左，右手时靠右

**智感握姿**：
- 单手 → 工具栏简化（仅 B/I），向握持侧靠拢
- 双手 → 工具栏完整展开
- 平放桌面 → 全屏阅读，顶栏底栏隐藏

**顶部返回按钮**：
- 点 ← → 退出到项目工作台（专业模式）/ 项目列表（普通模式）

### 4.2 素材 Tab — 设定子Tab

**布局**：分段标题（人物 / 世界观），非子Tab切换

```
┌──────────────────────────────┐
│  ← 书名                       │
├──────────────────────────────┤
│  ▎人物                        │
│  ┌──────┐ ┌──────┐ ┌──────┐  │
│  │ 周砚  │ │ 林晚  │ │ +添加 │  │  ← 横向卡片
│  └──────┘ └──────┘ └──────┘  │
│                               │
│  ▎世界观                      │
│  ┌──────┐ ┌──────┐ ┌──────┐  │
│  │苍梧城 │ │云州   │ │ +添加 │  │
│  └──────┘ └──────┘ └──────┘  │
└──────────────────────────────┘
```

### 4.3 素材 Tab — 灵感子Tab

```
┌──────────────────────────────┐
│  ← 书名                       │
├──────────────────────────────┤
│  本书灵感·《小说A》             │
│  ┌────┐ ┌────┐ ┌────┐ ┌───┐ │
│  │灵1 │ │灵2 │ │灵3 │ │更多│ │  ← 横向，前两行文本预览
│  └────┘ └────┘ └────┘ └───┘ │
│                               │
│  全部灵感                      │
│  ┌────┐ ┌────┐ ┌────┐ ┌───┐ │
│  │灵A │ │灵B │ │灵C │ │更多│ │
│  └────┘ └────┘ └────┘ └───┘ │
│                               │
│  FAB ┌───┐                    │
│      │ + │ 新建灵感           │
│      └───┘                    │
└──────────────────────────────┘
```

**FAB 点击** → 跳转灵感创建页：
- 归属选择：本书（默认选中）/ 其他书 → / 暂不归类（三个平铺大按钮）
- 内容输入区
- 保存按钮

**"更多"点击** → 全屏列表页（搜索 + 按书籍筛选 + 按时间排序）

### 4.4 关系 Tab

```
┌──────────────────────────────┐
│  ← 书名            🔍 筛选 整理 │
├──────────────────────────────┤
│                              │
│  ┌──────┐    恋人    ┌──────┐ │
│  │ 林晚  │──────────│ 周砚  │ │
│  └──────┘          └──┬───┘ │
│                 师兄    │     │
│               ┌────────┘     │
│          ┌────┴─────┐        │
│          │  江屿川   │        │
│          └──────────┘        │
│                              │
└──────────────────────────────┘
```

**交互**：
- 单指拖动节点/平移画布
- 双指缩放
- 点击节点 → 底部浮出速览卡 → 再点进入人物详情
- 长按节点 → 编辑/删除/跳转
- 从节点A向节点B滑动 → 进入连线模式 → 弹出关系标签选择半屏（正面/中立/负面 + 自定义 + 备注）
- 双击空白处 → 新建人物节点
- 双击人物 → 聚焦模式（只显示一度关系）
- 右上角筛选 → 按章节筛选（当前章节人物高亮，其余灰显）

**自动生成**：从已有人物卡自动生成节点——打开即有图，用户只补充连线和标签。

**与编辑Tab联动**：从编辑页跳转过来时，当前章节涉及的人物节点高亮（外圈绿色光晕），其余灰显（50%透明度）。

### 4.5 人物详情页

**预设字段**：

- 字段：类型；必填
- 姓名：单行文本；✅
- 别名：单行文本；—
- 年龄：单行文本；—
- 外貌：多行文本；—
- 性格：多行文本；—
- 背景故事：多行文本；—
- 备注：多行文本；—

**交互**：
- 新建：输入姓名 → 确认 → 进入详情页，7字段就位
- 空字段显示浅灰占位文字
- 长按字段 → 上移/下移/隐藏
- 右上角+ → 添加自定义字段
- 右上角模板 → 切换模板
- 顶栏：撤销/重做常驻
- 底部自动聚合：关联章节列表 + 关系跳转入口

### 4.6 世界设定详情页

**预设字段**：

- 字段：类型；必填
- 名称：单行文本；✅
- 类别：单选标签；✅（地理/政治/历史/魔法科技/种族/文化/其他）
- 所属区域：单行文本；—
- 描述：多行文本；✅
- 备注：多行文本；—

### 4.7 启动流程与引导页


#### 4.7.1 系统启动页（Splash）

启动页是系统级开屏，在冷启动时由系统渲染。配置在 `module.json5` 中：

```json5
// products/default/src/main/module.json5
{
  "app": {
    "splash": {
      "startWindowIcon": "$media:app_icon",
      "startWindowBackground": "#EDF5EA",     // green_50 浅色 / #1A2818 深色
      "startWindowBackgroundMode": "color"
    }
  }
}
```

**设计约束**：
- 纯图标类结构（品牌强化）：应用图标 + 背景色 `#EDF5EA`（green_50），与主页面全局背景同色系
- 静态设计，无动画/交互元素，0.3–0.8 秒内完成过渡
- 不包含促销、广告、第三方品牌
- 深色模式背景改为 `#1A2818`
- 多设备自动适配（系统根据断点缩放图标和调整布局）

#### 4.7.2 隐私合规弹窗（标准化托管）

根据华为应用市场审核 Checklist 要求：**应用首次启动时必须显著提示用户阅读隐私政策。** Weaver 使用鸿蒙「标准化隐私声明托管服务」——由系统自动弹出标准化隐私弹窗，代码层面无需任何实现。

**配置方式**（零代码）：

1. 在 AppGallery Connect → 我的应用 →「管理隐私声明」中填写隐私政策 URL 和用户协议 URL
2. 系统在用户首次打开应用时自动弹出标准化弹窗
3. 用户点击「同意」后进入引导页；点击「不同意并退出」则退出应用

**系统弹窗样式**（系统统一，不可自定义）：

```
┌─────────────────────────────┐
│                             │
│       [Weaver 图标]          │
│                             │
│   欢迎使用 Weaver            │
│                             │
│  ┌───────────────────────┐  │
│  │  📋 隐私政策           │  │  ← 可点击查看全文
│  │  📋 用户协议           │  │  ← 可点击查看全文
│  │                       │  │
│  │  点击"同意"即表示您    │  │
│  │  已阅读并同意上述协议   │  │
│  │                       │  │
│  │  [ 不同意并退出 ]      │  │
│  │  [     同意     ]     │  │  ← 品牌主色按钮
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

#### 4.7.3 引导页（首次启动，3 页轮播）

用户通过隐私弹窗后，进入 3 页引导流程。采用 Swiper 轮播，左右箭头翻页，底部圆点指示器。最后一页点击卡片直接进入编辑器。

**设计原则**：

- 原则：说明
- **3 页上限**：行业最佳实践中位数，用户注意力不超载
- **渐进决策**：第 1 页：你是谁 → 第 2 页：你能做什么 → 第 3 页：从哪里开始
- **所见即所得**：第 2 页展示实际界面截图，不是抽象插画
- **可逆承诺**：第 3 页底部标注"可在设置中随时切换"，消除选择焦虑
- **无强制登录**：所有页面不出现登录要求，先体验价值

---

**第 1 页 — 品牌认知**

```
┌─────────────────────────────────────┐
│                                     │
│          🧶  [应用图标 + 柔和光晕]    │
│                                     │
│          欢迎使用 Weaver             │  ← gray_900，32fp，Bold
│                                     │
│       为长篇小说创作者而生            │  ← gray_700，18fp
│     人物 · 世界观 · 关系图           │
│          一站管理                    │
│                                     │
│         [  ←  1/3  →  ]            │  ← 左右箭头 + 页码
│          · ○ ○                     │  ← 页码指示器（当前页 green_500）
│                                     │
│           跳过引导                   │  ← gray_300，14fp，文字链接
└─────────────────────────────────────┘
```

- **定位**：用户打开应用看到的第一个设计内容（隐私弹窗之后），建立品牌信任
- **设计考量**：品牌在第一页即建立，避免拖到引导流程末尾

**交互**：
- 点 `→` 或左滑 → 第 2 页
- 点「跳过引导」→ 直接跳到第 3 页（模式选择）
- 无「上一步」（第 1 页不提供后退）

---

**第 2 页 — 功能预览**

```
┌─────────────────────────────────────┐
│                                     │
│        你的创作工具箱                │  ← gray_900，28fp，Bold
│                                     │
│  ┌───────────────┐ ┌──────────────┐│
│  │               │ │              ││
│  │  [编辑器截图]  │ │ [素材+关系图] ││  ← 两张实际界面截图
│  │   Markdown    │ │  人物卡      ││     圆角 16vp，阴影
│  │   写作区域    │ │  关系图连线  ││
│  │               │ │              ││
│  └───────────────┘ └──────────────┘│
│                                     │
│  所见即所得 — 这就是你的写作界面     │  ← gray_700，14fp
│                                     │
│         [  ←  2/3  →  ]            │
│          ○ · ○                     │
└─────────────────────────────────────┘
```

- **定位**：用实际截图告诉用户"你即将使用的就是这个界面"，不堆砌功能说明文字
- **设计考量**：使用实际界面截图让用户预览功能，压缩为一页汇总

**交互**：
- 点 `←` → 第 1 页，点 `→` → 第 3 页

---

**第 3 页 — 模式选择**

```
┌─────────────────────────────────────┐
│                                     │
│       选择你的写作方式               │  ← gray_900，28fp，Bold
│                                     │
│  ┌────────────────┐ ┌──────────────┐│
│  │                │ │              ││
│  │  [编辑器截图]   │ │ [素材+关系图] ││  ← 两张卡片
│  │                │ │              ││     圆角 16vp
│  │                │ │              ││     阴影 0 4vp 12vp rgba(0,0,0,0.08)
│  │   ✏️ 日常写作   │ │  📦 小说创作  ││     按下缩放 0.97x → 绿色描边
│  └────────────────┘ └──────────────┘│
│                                     │
│      可在设置中随时切换              │  ← gray_300，14fp
│                                     │
│         [  ←  3/3  ]               │  ← 无右箭头（最后一页）
│          ○ ○ ·                     │
└─────────────────────────────────────┘
```

- **定位**：整个引导的唯一决策点。点击卡片即进入，无额外操作
- **设计考量**：采用"简洁清爽 vs 专业高效"的双卡片模式，让用户直观选择写作方式

**交互**：
- 点击「日常写作」卡片 → 进入普通模式编辑器（2 Tab）
- 点击「小说创作」卡片 → 进入专业模式编辑器（4 Tab）
- 卡片按下：绿色描边 `green_500` 2vp，缩放 0.97x（100ms），抬起回弹（200ms spring）
- 点 `←` → 回到第 2 页

---

#### 4.7.4 启动路由决策（MainAbility）

```typescript
// products/default/src/main/ets/entryability/MainAbility.ets
import UIAbility from '@ohos.app.ability.UIAbility'
import window from '@ohos.window'
import AppStorage from '@ohos.app.storage.AppStorage'
import PersistentStorage from '@ohos.app.storage.PersistentStorage'

export default class MainAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage) {
    // 隐私弹窗由系统托管，MainAbility 被调用 = 用户已同意隐私政策
    // 检查是否首次启动（无存储记录时默认 true）
    const isFirstLaunch = AppStorage.get<boolean>('weaver_guided') ?? true

    if (isFirstLaunch) {
      // 首次启动 → 3 页引导
      windowStage.loadContent('pages/GuideSwiperPage', (err) => {
        if (err.code) console.error('GuideSwiperPage load failed:', JSON.stringify(err))
      })
    } else {
      // 非首次 → 直接进入编辑器（上次退出时的位置）
      windowStage.loadContent('pages/EditorPage', (err) => {
        if (err.code) console.error('EditorPage load failed:', JSON.stringify(err))
      })
    }
  }
}
```

#### 4.7.5 引导页 Swiper 实现（GuideSwiperPage）

```typescript
// products/default/src/main/ets/pages/GuideSwiperPage.ets
import router from '@ohos.router'
import AppStorage from '@ohos.app.storage.AppStorage'
import PersistentStorage from '@ohos.app.storage.PersistentStorage'

@Entry
@Component
struct GuideSwiperPage {
  @State currentIndex: number = 0
  private totalPages: number = 3
  private swiperController: SwiperController = new SwiperController()

  // ===== 品牌页 =====
  @Builder
  PageBrand() {
    Column() {
      // 图标
      Image($r('app.media.app_icon'))
        .width(120).height(120)
        .borderRadius(28)
        .shadow({ radius: 24, color: 'rgba(122,183,95,0.25)' }) // green_500 光晕

      Text('欢迎使用 Weaver')
        .fontSize(32).fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .margin({ top: 32 })

      Text('为长篇小说创作者而生')
        .fontSize(18).fontColor('#4A4A4A')
        .margin({ top: 16 })

      Text('人物 · 世界观 · 关系图，一站管理')
        .fontSize(16).fontColor('#9E9D9D')
        .margin({ top: 8 })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
  }

  // ===== 功能预览页 =====
  @Builder
  PagePreview() {
    Column() {
      Text('你的创作工具箱')
        .fontSize(28).fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .margin({ bottom: 32 })

      Row({ space: 16 }) {
        // 编辑器截图
        Column() {
          Image($r('app.media.guide_editor'))
            .width('100%').layoutWeight(1)
            .objectFit(ImageFit.Contain)
          Text('Markdown 写作').fontSize(14).fontColor('#4A4A4A').padding(12)
        }
        .width('44%').borderRadius(16)
        .backgroundColor('#F2F2F2')

        // 素材+关系图截图
        Column() {
          Image($r('app.media.guide_material'))
            .width('100%').layoutWeight(1)
            .objectFit(ImageFit.Contain)
          Text('素材 · 关系图').fontSize(14).fontColor('#4A4A4A').padding(12)
        }
        .width('44%').borderRadius(16)
        .backgroundColor('#F2F2F2')
      }
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 24 })

      Text('所见即所得 — 这就是你的写作界面')
        .fontSize(14).fontColor('#9E9D9D')
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
  }

  // ===== 模式选择页 =====
  @Builder
  PageModeSelect() {
    Column() {
      Text('选择你的写作方式')
        .fontSize(28).fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .margin({ bottom: 32 })

      Row({ space: 24 }) {
        ModeCard({
          image: $r('app.media.guide_normal'),
          icon: '✏️',
          title: '日常写作',
          desc: '简洁编辑器，随时记录',
          onClick: () => this.enterApp('normal')
        })

        ModeCard({
          image: $r('app.media.guide_professional'),
          icon: '📦',
          title: '小说创作',
          desc: '人物、世界观、关系图',
          onClick: () => this.enterApp('professional')
        })
      }
      .justifyContent(FlexAlign.Center)

      Text('可在设置中随时切换')
        .fontSize(14).fontColor('#9E9D9D')
        .margin({ top: 32 })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
  }

  enterApp(mode: string) {
    AppStorage.setOrCreate('weaver_mode', mode)
    AppStorage.setOrCreate('weaver_guided', true)
    PersistentStorage.persistProp('weaver_guided', true)
    router.replaceUrl({ url: 'pages/EditorPage' })
  }

  skipGuide() {
    this.swiperController.changeIndex(2) // 跳到最后一页做模式选择
  }

  build() {
    Stack() {
      Swiper(this.swiperController) {
        this.PageBrand()
        this.PagePreview()
        this.PageModeSelect()
      }
      .index(this.currentIndex)
      .indicator(false) // 使用自定义指示器
      .loop(false)
      .width('100%').height('100%')
      .onChange((index: number) => {
        this.currentIndex = index
      })

      // 跳过引导（仅第 1、2 页显示）
      if (this.currentIndex < 2) {
        Text('跳过引导')
          .fontSize(14).fontColor('#9E9D9D')
          .position({ x: '80%', y: '8%' })
          .onClick(() => this.skipGuide())
      }

      // 左箭头
      if (this.currentIndex > 0) {
        Button() {
          Image($r('sys.media.ohos_ic_public_arrow_left'))
            .width(24).height(24).fillColor('#1A1A1A')
        }
        .width(44).height(44)
        .backgroundColor('#F2F2F2').borderRadius(22)
        .position({ x: 24, y: '88%' })
        .onClick(() => {
          this.swiperController.showPrevious()
        })
      }

      // 右箭头（最后一页不显示）
      if (this.currentIndex < 2) {
        Button() {
          Image($r('sys.media.ohos_ic_public_arrow_right'))
            .width(24).height(24).fillColor('#1A1A1A')
        }
        .width(44).height(44)
        .backgroundColor('#F2F2F2').borderRadius(22)
        .position({ x: '92%', y: '88%' })
        .onClick(() => {
          this.swiperController.showNext()
        })
      }

      // 页码指示器
      Row({ space: 8 }) {
        ForEach([0, 1, 2], (index: number) => {
          Circle({ width: 8, height: 8 })
            .fill(index === this.currentIndex ? '#7AB75F' : '#D5D5D5')
        })
      }
      .position({ x: '50%', y: '89%' })
      .translate({ x: '-50%' })
    }
    .width('100%').height('100%')
    .backgroundColor('#FFFFFF')
  }
}

// ===== 模式选择卡片组件 =====
@Component
struct ModeCard {
  @Prop image: Resource
  @Prop icon: string
  @Prop title: string
  @Prop desc: string
  onClick: () => void = () => {}
  @State pressed: boolean = false

  build() {
    Column() {
      Image(this.image)
        .width('100%').layoutWeight(1)
        .objectFit(ImageFit.Contain)
        .borderRadius({ topLeft: 16, topRight: 16 })

      Column() {
        Row({ space: 6 }) {
          Text(this.icon).fontSize(20)
          Text(this.title)
            .fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
        }
        .margin({ bottom: 4 })

        Text(this.desc)
          .fontSize(13).fontColor('#9E9D9D')
      }
      .width('100%').padding(16)
      .backgroundColor('#F2F2F2')
      .borderRadius({ bottomLeft: 16, bottomRight: 16 })
    }
    .width('40%').height('50%')
    .borderRadius(16)
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.08)', offsetY: 4 })
    .scale({ x: this.pressed ? 0.97 : 1, y: this.pressed ? 0.97 : 1 })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .border({ width: this.pressed ? 2 : 0, color: '#7AB75F' })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.pressed = true
      if (event.type === TouchType.Up) {
        this.pressed = false
        this.onClick()
      }
    })
  }
}
```

#### 4.7.6 多设备适配

- 断点：第 1 页图标；第 2 页截图卡片；第 3 页模式卡片；箭头按钮
- sm（手机竖屏）：120×120vp；各 44% 宽，上下排列；各 40% 宽，50% 高；44×44vp
- sm（手机横屏）：100×100vp；各 38% 宽；各 36% 宽，58% 高；44×44vp
- md（平板竖屏）：150×150vp；各 40% 宽；各 340vp 宽，460vp 高；48×48vp
- lg（平板横屏/PC）：180×180vp；各 36% 宽；各 420vp 宽，520vp 高；56×56vp

#### 4.7.7 完整启动流程

```
冷启动
  │
  ▼
系统渲染 Splash 启动页（0.3–0.8s）
  │
  ▼
MainAbility.onCreate()
  │
  ▼
[系统检测：是否首次安装？]
  ├── 是 → 系统弹出标准化隐私弹窗
  │         ├── 用户点「不同意并退出」→ 退出应用
  │         └── 用户点「同意」
  │               │
  │               ▼
  │          MainAbility 判断首次启动 → GuideSwiperPage（3 页引导）
  │               │
  │               └── 用户在第 3 页点击卡片 → EditorPage（光标就位）
  │
  └── 否 → EditorPage（恢复上次状态，光标就位）
```





---

## 五、数据模型

### 5.1 Book（书籍）
```
{
  id: string,
  name: string,
  createdAt: number,
  updatedAt: number,
  mode: 'normal' | 'professional'
}
```

### 5.2 Chapter（章节）
```
{
  id: string,
  bookId: string,
  title: string,
  content: string,       // Markdown格式
  order: number,
  wordCount: number,
  createdAt: number,
  updatedAt: number
}
```

### 5.3 Character（人物）
```
{
  id: string,
  bookId: string,
  name: string,
  alias: string,
  age: string,
  appearance: string,
  personality: string,
  background: string,
  notes: string
}
```

### 5.4 WorldSetting（世界设定）
```
{
  id: string,
  bookId: string,
  name: string,
  category: 'geography' | 'politics' | 'history' | 'magic_tech' | 'race' | 'culture' | 'other',
  region: string,
  description: string,
  notes: string
}
```

### 5.5 Inspiration（灵感）
```
{
  id: string,
  bookId: string | null,  // null = 暂不归类
  content: string,
  createdAt: number
}
```

### 5.6 Relationship（关系）
```
{
  id: string,
  bookId: string,
  characterIdA: string,
  characterIdB: string,
  type: 'positive' | 'neutral' | 'negative' | 'indirect',
  label: string,          // 恋人/师兄/敌对 等
  notes: string
}
```

---

## 六、鸿蒙特性集成清单

- 特性：集成位置；说明
- Agent Framework Kit：编辑器、关系图、人物详情页；半屏唤起智能体：一致性检查、定位、卡壳讨论
- 智感握姿：编辑器FAB、工具栏；单/双手状态切换UI模式
- 实况窗：写作进行中；锁屏显示实时字数+计时，结束自动清除
- 闪控球：全系统；跨应用一键切入写作 + 写作计时
- 互动卡片：桌面；一键跳转上次编辑位置
- 碰一碰精准分享：编辑器；段落从手机精准插入平板文档指定位置
- AI隔空传送：编辑器；跨设备传输段落/文档
- 应用接续：全局；手机→平板→PC无缝流转
- 沉浸光感组件：编辑器；纸面质感视觉
- LTPO可变帧率：编辑器；码字低帧省电，翻页高帧流畅
- 隐私防窥：编辑器；切换应用时遮盖内容
- 一多适配：全局；手机/Pad/PC/二合一全端部署
- Core Vision Kit（文搜图）：灵感图库；语义搜索本地图片

---

## 七、色彩系统完整规范

> 基于 HarmonyOS 色彩 Token 体系，主色调提取自北京语言大学校徽：北语绿（#7AB75F）+ 经纬线灰（#6F6E6E）。色阶以基准色沿 HSL 明度轴生成，色相保持 ±2°。

### 7.1 主色·北语绿色阶

- Token：色值；浅色模式用途；深色模式色值；深色模式用途
- green_900：#2D4423；—（浅色不常用）；#A4CE92；强调、闪控球暗态
- green_700：#4A6E39；按钮按下、选中标签；#7AB75F；按钮主色
- green_500：**#7AB75F**；品牌主色/按钮/FAB/Tab选中；#8DC97A；交互主色（+5%明度）
- green_300：#A4CE92；次要按钮、标签；#4A6E39；容器边线
- green_100：#D3E9CB；选中浅底、输入聚焦；#2D4423；选中底色
- green_50：#EDF5EA；页面全局背景；#1A2818；全局背景

### 7.2 辅色·经纬线灰色阶

- Token：色值；浅色模式用途；深色模式色值；深色模式用途
- gray_900：#1A1A1A；正文标题；#E8E8E8；正文标题
- gray_700：#4A4A4A；次要正文、时间戳；#B0B0B0；次要文字
- gray_500：**#6F6E6E**；Tab未选中、辅助说明；#8A8A8A；辅助文字
- gray_300：#9E9D9D；占位、禁用；#5C5C5C；禁用态
- gray_100：#D5D5D5；分割线、卡片边框；#3A3A3A；分割线
- gray_50：#F2F2F2；次级背景、侧滑栏；#242424；次级背景

### 7.3 鸿蒙 Token 语义映射

- Token：浅色；深色；应用场景
- background_primary：#EDF5EA；#1A2818；App 全局底色
- background_card：#FFFFFF；#1E1E1E；卡片、编辑器、弹窗
- background_surface：#F2F2F2；#242424；侧滑栏、Tab栏
- font_primary：#1A1A1A；#E8E8E8；标题、正文
- font_secondary：#4A4A4A；#B0B0B0；次要文字、时间
- font_tertiary：#9E9D9D；#5C5C5C；占位、禁用、辅助
- interactive_primary：#7AB75F；#8DC97A；主按钮、FAB、选中态
- interactive_hover：#4A6E39；#7AB75F；按钮按下
- interactive_secondary：#A4CE92；#4A6E39；次要按钮、标签
- container_primary：#D3E9CB；#2D4423；选中卡片底
- border_default：#D5D5D5；#3A3A3A；分割线、边框
- brand_primary：#7AB75F；#8DC97A；品牌色
- on_brand_primary：#FFFFFF；#1A1A1A；品牌色上文字

### 7.4 关系图节点色

- 节点：形状；色值；说明
- 主角：圆形；#E67E22；暖橙——全图唯一暖色，一眼定位
- 配角：圆形；#689F63；深绿——主色同源
- 反派：圆形；#4A4A4A；灰系——距离感
- 组织/势力：菱形；#A4CE92；绿系
- 地点：方形；#9E9D9D；灰系

当前章节关联节点：原色 + 外圈 #7AB75F 2dp 光晕。非关联节点：原色叠加 50% 透明度。

### 7.5 关系图连线色

- 关系：线型；色值
- 正面（恋人/家人/朋友）：实线；#A4CE92
- 中立（同学/同事）：实线；#9E9D9D
- 负面（敌对/背叛）：虚线；#6F6E6E
- 间接/过去关系：虚线；#D5D5D5

### 7.6 状态反馈色

- 状态：浅色；深色
- 完成/成功：#4A8C7C；#5DAF9A
- 警告/待处理：#D4A53D；#E0B84C
- 错误/危险：#C0392B；#E74C3C

### 7.7 各页面色彩应用

- 元素：浅色；深色
- 全局背景：#EDF5EA；#1A2818
- 编辑器背景：#FFFFFF；#1E1E1E
- 灵感/人物/设定卡片：#FFFFFF + gray_100 边框；#1E1E1E + #3A3A3A 边框
- FAB：green_500 + 白色图标；#8DC97A + gray_900 图标
- Tab选中：green_500；#8DC97A
- Tab未选中：gray_500；#8A8A8A
- 主按钮：green_500 + 白字；#8DC97A + gray_900字
- 顶栏：#FFFFFF + gray_900字；#1E1E1E + #E8E8E8字
- 实况窗计时：green_500；#8DC97A
- 闪控球：green_500 + 白图标；#8DC97A + gray_900图标
- Agent半屏：#FFFFFF + green_100 分隔；#1E1E1E + green_900 分隔
- 隐私防窥遮罩：green_900 85%透明度；green_900 95%透明度

### 7.8 圆角规范

- 圆角：适用场景
- 4vp：标签、角标
- 8vp：图片、图标、人物/设定卡缩略图
- 16vp：灵感卡片、人物卡、世界设定卡、通知卡片
- 20vp：按钮、菜单、FAB、选项卡
- 32vp：半模态弹窗、Agent对话窗、关系标签选择窗

原则：同层统一、层级正相关。

### 7.9 使用规则

1. 主色不出现于正文区域——正文只用文字色+背景色
2. 每视图状态反馈色不超过两种——关系图节点色例外
3. 深色模式不由浅色简单反色——背景用绿调黑（#1A2818），编辑器用微暖黑（#1E1E1E），文字用 #E8E8E8 替代纯白
4. 文字对比度全线保持 WCAG AA 级（正文 ≥4.5:1）

---

## 八、Agent 写作伴侣设计

### 唤起方式
- 编辑器顶栏 🤖 图标
- 人物详情页顶栏
- 关系图页顶栏
- 任何页面的半屏弹窗唤起

### 对话能力

- 唤起位置：做什么
- 编辑器中："上次写到哪了" / "卡壳了，帮我讨论情节"
- 关系图页："检查周砚和林晚的关系在第3章和第8章是否一致"
- 人物详情页："这个人物还有什么设定漏洞"
- 首页："今天推荐写哪个项目"

### 约束
- 所有创作数据本地存储，不上云
- Agent不代笔写作

---

## 九、开发环境与工具链

- **IDE**：DevEco Studio 6.0.0 Release
- **SDK**：HarmonyOS 7 (API 26)
- **语言**：ArkTS + ArkUI（声明式）
- **签名**：手动签名（非自动签名）
- **工程模板**：`Flexible Layout Ability`（三层架构模板）

---

## 十、一多适配开发规范

> 本节基于华为「一次开发，多端部署」技术体系，为 DevEco Code 提供可直接生成代码的开发规范。

### 10.1 工程架构：三层架构

使用 DevEco Studio 创建工程时选择 **Flexible Layout Ability** 模板，自动生成三层结构：

```
/Weaver
 ├── common/                  # 公共层（HAR）
 │   └── src/main/ets/        #   → 通用组件、工具类、色彩Token常量
 │
 ├── features/                # 功能模块层（HAR）
 │   ├── editor/              #   → 编辑器模块
 │   ├── material/            #   → 素材管理模块（人物/世界观/灵感）
 │   ├── relationship/        #   → 关系图模块
 │   ├── agent/               #   → Agent 半屏对话模块
 │   └── settings/            #   → 设置模块
 │
 └── products/
     └── default/             # 主入口（HAP，phone + tablet + 2in1）
         └── src/main/
             ├── ets/pages/   #   → 各页面
             └── module.json5 #   → deviceTypes: ["phone", "tablet", "2in1"]
```

**依赖规则**：`products/default` → 依赖 → `features/*` → 依赖 → `common`。在 `oh-package.json5` 中声明：

```json5
// products/default/oh-package.json5
"dependencies": {
  "@ohos/editor": "file:../../features/editor",
  "@ohos/material": "file:../../features/material",
  "@ohos/relationship": "file:../../features/relationship",
  "@ohos/common": "file:../../common"
}
```

修改后点击 **Sync Now** 生效。

### 10.2 断点系统（Breakpoint System）

断点是页面布局切换的判断条件。系统提供**横向断点**（基于窗口宽度 vp）和**纵向断点**（基于宽高比）。

- 断点：宽度范围（vp）；典型设备；本应用适配策略
- **sm**：0 ≤ w < 600；手机竖屏、折叠屏折叠态；单列布局，底部Tab导航
- **md**：600 ≤ w < 840；手机横屏、折叠屏展开、小平板竖屏；分栏布局，侧边Tab导航
- **lg**：840 ≤ w；平板横屏、PC、二合一；侧边导航栏 + 内容区分栏

**ArkTS 实现**：

```typescript
// common/src/main/ets/utils/BreakPoint.ets
export enum BreakPoint {
  SM = 0,
  MD = 1,
  LG = 2
}

@AppStorage('currentBreakPoint') currentBreakPoint: BreakPoint = BreakPoint.SM

// 在入口页面监听窗口变化
.onWidthChange((width: number) => {
  if (width < 600) AppStorage.set('currentBreakPoint', BreakPoint.SM)
  else if (width < 840) AppStorage.set('currentBreakPoint', BreakPoint.MD)
  else AppStorage.set('currentBreakPoint', BreakPoint.LG)
})
```

### 10.3 栅格系统（Grid System）

鸿蒙提供窗口级栅格，跟随窗口宽度自动调整 Columns 数量。**本应用不自行实现栅格**，统一使用系统 `GridRow` / `GridCol`。

- 窗口宽度（vp）：Columns；Margin；Gutter
- 0 ≤ w < 600：4；16vp；8vp
- 600 ≤ w < 840：8；24vp；12vp
- 840 ≤ w：12；32vp；16vp

- **最大使用宽度**：2220vp，超出时内容区居中。
- **单位**：所有布局尺寸使用 **vp**（虚拟像素），字体使用 **fp**。
- **网格基准**：8vp 系统 → 所有间距、圆角对齐 4vp 或 8vp 的倍数。

### 10.4 响应式布局方法（8 种，本应用选用表）

- 方法：适用场景（本应用）；断点触发条件
- **自适应拉伸**：编辑器正文宽度、灵感卡片间距；全断点生效，`layoutWeight`
- **自适应缩放**：关系图节点（保持圆形）；等比缩放，`aspectRatio`
- **自适应延伸**：人物卡/世界观卡横向列表；≥ md 时显示更多卡片
- **自适应折行**：灵感卡片从横向折叠为多行网格；窗口变小时折行
- **挪移布局**：关系图从"上图下文字"→"左图右文字"；横竖屏切换
- **重复布局**：设定卡从 1 列 → 2 列 → 3 列；md 起双列，lg 起三列
- **分栏布局**：侧滑栏 + 编辑器 左右分栏；≥ 600vp 时分栏，默认 4:6
- **缩进布局**：编辑器正文在宽屏时自动缩进；lg 断点，正文区 8 column 缩进

### 10.5 导航架构多端适配

本应用的导航根据断点自动切换，**无需两套代码**：

- 断点：导航方式；实现
- **sm**（手机竖屏）：底部 TabBar；`Tabs({ barPosition: BarPosition.End })`
- **md**（手机横屏/小平板）：侧边 Tab；`Tabs({ barPosition: BarPosition.Start, vertical: true })` 宽度 72vp
- **lg**（平板/PC）：侧边导航栏（可收起）；`Navigation` + `NavRouter`，侧栏默认展开 240vp，点击汉堡图标收起至 72vp

**切换逻辑**（写在入口页 `@Component` 中）：

```typescript
@StorageLink('currentBreakPoint') breakPoint: BreakPoint = BreakPoint.SM

build() {
  if (this.breakPoint === BreakPoint.SM) {
    // 底部 Tab：5个TabItem，只显示icon
    Tabs({ barPosition: BarPosition.End }) { /* ... */ }
  } else if (this.breakPoint === BreakPoint.MD) {
    // 侧边 Tab：竖向排列，72vp宽
    Tabs({ barPosition: BarPosition.Start, vertical: true }) { /* ... */ }
    .barWidth(72)
  } else {
    // 侧边导航栏：Navigation组件，内容区 + 侧栏
    Navigation() { /* ... */ }
    .navBarWidth(240)  // 展开
    .hideNavBar(false)
  }
}
```

**编辑页分栏适配**（≥ 600vp 时侧滑栏常驻左侧）：

```typescript
// 编辑页
if (this.breakPoint === BreakPoint.SM) {
  // 侧滑栏为 drawer 式，点击 ☰ 滑出
  Navigation() { /* 编辑器 */ }
    .mode(NavigationMode.Stack)
} else {
  // 侧滑栏常驻左侧，分栏 4:6
  Navigation() { /* 章节列表 */ }
    .mode(NavigationMode.Split)
    .navBarWidth((width * 0.4))
}
```

### 10.6 各页面多端适配策略速查

- 页面：sm (手机)；md (小平板/横屏)；lg (平板/PC)
- **编辑器**：全屏单列，drawer侧滑栏；分栏：章节列表(4) + 编辑器(6)；分栏 + 右侧Agent面板
- **素材-设定**：人物卡横向滑动 2.5 列露出；固定 3 列网格；固定 4 列网格
- **素材-灵感**：横向滑动卡片；双行网格 `4×2`；三行网格 `5×3`
- **关系图**：全屏触控画布；左图(6) + 右信息(4)；左图(7) + 右信息(3) + Agent面板
- **设定创建页**：全屏单表单；居中卡片，左右留白 20%；居中卡片最大宽 800vp
- **我的**：单列列表；双列列表（设置项铺开）；居中卡片式 + 右侧预览

### 10.7 安全区与避让

- **手机**：避让顶部状态栏 + 底部导航条；FAB 避开底部安全区 16vp 上移。
- **折叠屏**：关键交互避开转轴折痕区（折叠屏展开态折痕 ±16vp）。
- **平板**：分屏模式下按实际窗口尺寸计算栅格，不是屏幕尺寸。

### 10.8 多设备工程部署

- `module.json5` 中 `deviceTypes` 声明为 `["phone", "tablet", "2in1"]`
- 仅一个 entry 型 HAP，手机/平板/二合一共用
- 发布时在 AppGallery Connect 勾选对应设备类型
- 增强启动页（API 19+）按断点配置不同资源

### 10.9 数据存储

详见 **第十二节：ArkData 数据持久化与同步方案**。

---

## 十一、MVP范围（初赛可交付）

- 必须：可选/后续
- 引导页 + 双模式切换：深色模式
- 编辑器（纯文本+Markdown）：稿纸背景主题
- 侧滑栏书籍/章节管理：云同步
- FAB + 智感握姿：碰一碰精准分享
- 一多适配（手机/平板/PC）：AI隔空传送
- 实况窗写作计时：文段图片分享
- 闪控球快捷入口：文搜图灵感检索
- 素材Tab：人物/世界观卡片：Agent跨章节一致性检查
- 素材Tab：灵感备忘录
- 关系Tab：可视化关系图
- Agent半屏唤起
- 隐私防窥
- 沉浸光感组件

---

## 十二、ArkData 数据持久化与同步方案

> 基于 ArkData（方舟数据管理）框架，为 DevEco Code 提供可直接生成代码的数据层实现规范。参考来源：华为 ArkData 官方文档与开发者最佳实践。

### 12.1 ArkData 框架概述

ArkData 是 HarmonyOS 统一的数据管理框架，覆盖「存储 → 管理 → 同步」全场景。核心模块：

- 模块：用途
- 标准化数据定义（UDMF）：跨应用、跨设备的统一数据类型标准
- 数据存储：用户首选项 / 键值型数据库 / 关系型数据库
- 数据管理：权限管理、备份恢复、加密、DataShare 共享
- 数据同步：跨设备分布式同步、端云同步

**关键原则**：应用创建的数据库保存在应用沙盒中。卸载应用时，数据库自动删除。

### 12.2 存储组件选型

- 组件：核心特点；分布式同步；Weaver 适用场景
- **用户首选项（Preferences）**：轻量 KV，不支持分布式；❌；模式选择、是否首次启动、主题/稿纸偏好、字体大小
- **键值型数据库（KV-Store）**：KV，高性能，支持分布式；✅；写作计时器状态、闪控球配置、实况窗临时数据
- **关系型数据库（RelationalStore）**：表结构，SQL，支持加密/备份/分布式；✅；**主力**：书籍、章节、人物、世界设定、关系、灵感
- **分布式数据对象（DataObject）**：内存对象，跨设备实时同步；✅；跨设备编辑状态同步（后续版本）
- **DataShare**：跨应用数据共享接口；同设备；向外暴露灵感/人物数据供其他应用读取（后续）
- **UDMF**：跨应用拖拽/复制粘贴标准；✅；段落跨应用分享、灵感图片拖入（后续）

### 12.3 Weaver 数据层实施方案

#### 12.3.1 主力存储：关系型数据库（RelationalStore）

Weaver 的核心数据全部使用 `RelationalStore`，基于 SQLite 引擎，支持事务、加密和备份。

**建表 SQL**：

```sql
-- 书籍
CREATE TABLE IF NOT EXISTS books (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mode TEXT NOT NULL DEFAULT 'normal',  -- 'normal' | 'professional'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 章节
CREATE TABLE IF NOT EXISTS chapters (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',      -- Markdown 格式
  sort_order INTEGER NOT NULL DEFAULT 0,
  word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);

-- 人物
CREATE TABLE IF NOT EXISTS characters (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL,
  name TEXT NOT NULL,
  alias TEXT NOT NULL DEFAULT '',
  age TEXT NOT NULL DEFAULT '',
  appearance TEXT NOT NULL DEFAULT '',
  personality TEXT NOT NULL DEFAULT '',
  background TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);

-- 世界设定
CREATE TABLE IF NOT EXISTS world_settings (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'other',
  region TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);

-- 灵感
CREATE TABLE IF NOT EXISTS inspirations (
  id TEXT PRIMARY KEY,
  book_id TEXT,                           -- NULL = 暂不归类
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE SET NULL
);

-- 人物关系
CREATE TABLE IF NOT EXISTS relationships (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL,
  char_a_id TEXT NOT NULL,
  char_b_id TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'neutral',  -- 'positive' | 'neutral' | 'negative' | 'indirect'
  label TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
  FOREIGN KEY (char_a_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (char_b_id) REFERENCES characters(id) ON DELETE CASCADE
);
```

**ArkTS 数据库初始化**（在 `common/` 层实现）：

```typescript
// common/src/main/ets/database/DatabaseHelper.ets
import relationalStore from '@ohos.data.relationalStore'

const DB_NAME = 'Weaver.db'
const DB_VERSION = 1

export class DatabaseHelper {
  private store: relationalStore.RdbStore | null = null

  async init(context: Context): Promise<relationalStore.RdbStore> {
    if (this.store) return this.store

    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1  // 设备级加密
    }

    this.store = await relationalStore.getRdbStore(context, config)

    // 建表（首次初始化时自动执行）
    await this.createTables()
    return this.store
  }

  private async createTables(): Promise<void> {
    const sqls = [
      `CREATE TABLE IF NOT EXISTS books (...)`,  // 上述 SQL
      `CREATE TABLE IF NOT EXISTS chapters (...)`,
      `CREATE TABLE IF NOT EXISTS characters (...)`,
      `CREATE TABLE IF NOT EXISTS world_settings (...)`,
      `CREATE TABLE IF NOT EXISTS inspirations (...)`,
      `CREATE TABLE IF NOT EXISTS relationships (...)`
    ]
    for (const sql of sqls) {
      await this.store!.executeSql(sql)
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) throw new Error('Database not initialized')
    return this.store
  }

  async backup(): Promise<void> {
    await this.store!.backup('Backup.db')
  }

  async restore(): Promise<void> {
    await this.store!.restore('Backup.db')
  }
}

// 全局单例
export const dbHelper = new DatabaseHelper()
```

**章节 CRUD 示例**（features/editor 层）：

```typescript
// features/editor/src/main/ets/data/ChapterDao.ets
import relationalStore from '@ohos.data.relationalStore'
import { dbHelper } from '@ohos/common'

export class ChapterDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(chapter: Chapter): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: chapter.id,
      book_id: chapter.bookId,
      title: chapter.title,
      content: chapter.content,
      sort_order: chapter.order,
      word_count: chapter.wordCount,
      created_at: Date.now(),
      updated_at: Date.now()
    }
    await this.getStore().insert('chapters', valueBucket)
  }

  async update(id: string, content: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      content: content,
      word_count: content.length,  // 简化字数统计
      updated_at: Date.now()
    }
    const predicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async queryByBook(bookId: string): Promise<Chapter[]> {
    const predicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.orderByAsc('sort_order')
    const resultSet = await this.getStore().query(predicates)
    // 遍历 resultSet 构造 Chapter[]...
    return []
  }

  async delete(id: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }
}
```

#### 12.3.2 轻量配置：用户首选项（Preferences）

用于存储应用级偏好，不使用数据库。

```typescript
// common/src/main/ets/utils/PreferenceHelper.ets
import preferences from '@ohos.data.preferences'

const PREF_NAME = 'weaver_prefs'

export class PreferenceHelper {
  private prefs: preferences.Preferences | null = null

  async init(context: Context): Promise<void> {
    this.prefs = await preferences.getPreferences(context, PREF_NAME)
  }

  async getMode(): Promise<string> {
    return await this.prefs!.get('weaver_mode', 'normal') as string
  }

  async setMode(mode: string): Promise<void> {
    await this.prefs!.put('weaver_mode', mode)
    await this.prefs!.flush()
  }

  async isFirstLaunch(): Promise<boolean> {
    return await this.prefs!.get('weaver_guided', true) as boolean
  }

  async setGuided(): Promise<void> {
    await this.prefs!.put('weaver_guided', true)
    await this.prefs!.flush()
  }

  // 稿纸背景色、字体大小等偏好同理
}
```

#### 12.3.3 适用场景对照表

- 数据：存储方式；理由
- 书籍、章节（Markdown 内容）、人物、世界设定、关系、灵感：`RelationalStore`；结构化、需要 SQL 查询、有外键关联
- 模式选择（normal/professional）：`Preferences`；单一 KV，启动时需要快速读取
- 首次启动标记：`Preferences`；启动路由决策，需持久化且快速
- 稿纸背景色 / 字体大小 / 深色模式：`Preferences`；用户偏好，轻量
- 写作计时器临时状态：`AppStorage`（内存）；仅当前会话有效，不需要持久化

### 12.4 数据安全

#### 12.4.1 数据库加密

```typescript
// 创建数据库时指定安全等级
const config: relationalStore.StoreConfig = {
  name: 'Weaver.db',
  securityLevel: relationalStore.SecurityLevel.S1  // 设备级加密
}
```

安全等级说明：

- 等级：说明；Weaver 适用
- S1：设备解锁后可读写；✅ 默认等级
- S2：设备解锁后 + 用户认证后可读写；—
- S3：仅设备解锁后 + 特定条件下可读写；—
- S4：最高安全等级；—

#### 12.4.2 数据库备份与恢复

```typescript
// 备份（在「设置 → 数据管理」中触发）
await store.backup('Weaver_backup.db')

// 恢复
await store.restore('Weaver_backup.db')
```

**自动备份策略**（参考业界最佳实践）：
- 每次应用进入后台时，在 `onBackground()` 中自动备份到沙箱
- 保留最近 3 个备份版本
- 在「我的 → 数据管理」中提供手动备份/恢复入口

### 12.5 跨设备数据同步（后续版本）

Weaver 的本地优先架构决定了 **MVP 阶段不做跨设备同步**。但架构已预留扩展路径：

#### 12.5.1 关系型数据库跨设备同步

HarmonyOS 提供 `setDistributedTables()` 一键开启：

```typescript
// 后续版本中配置
store.setDistributedTables(['books', 'chapters', 'characters', 'world_settings',
  'inspirations', 'relationships'], (err) => {
  if (err) console.error('分布式配置失败:', err)
})
```

**工作原理**：
1. 调用 `setDistributedTables` 指定需要同步的表
2. DatamgrService 处理设备发现、数据传输和冲突解决
3. 采用**最终一致性**模型——设备不常在线时，重新组网后自动追平数据

**Weaver 的同步策略（后续设计）**：

- 策略：说明
- 同步范围：同华为账号、同应用的多设备间（手机 ↔ 平板 ↔ PC）
- 冲突处理：以最后修改时间戳为准（`updated_at` 字段）
- 初始同步：首次组网时全量同步，后续增量
- 离线支持：本地写入不受影响，重新组网后自动合并

#### 12.5.2 端云同步

HarmonyOS 提供 `@ohos.data.cloudData` 模块，支持 RelationalStore 与华为云空间同步：

```typescript
// 后续版本：开启端云同步
import cloudData from '@ohos.data.cloudData'

cloudData.enableCloud({
  bundleName: 'com.example.weaver',
  stores: [{ name: 'Weaver.db' }]
})
```

**MVP 阶段不启用**，但在 MVP 表格中标注为「后续版本」。

### 12.6 架构总结

```
┌─────────────────────────────────────────────┐
│                 UI 层（各页面组件）            │
├─────────────────────────────────────────────┤
│            数据访问层（DAO）                   │
│  ChapterDao / CharacterDao / BookDao / ...   │
├─────────────────────────────────────────────┤
│           DatabaseHelper（单例）              │
│     init() → RelationalStore（SQLite）        │
│     SecurityLevel.S1 加密                    │
├─────────────────────────────────────────────┤
│         PreferenceHelper（单例）              │
│     用户首选项 Preferences（KV）              │
├─────────────────────────────────────────────┤
│          沙箱文件系统（.md 导出/导入）          │
│          备份文件（Backup.db）                 │
├─────────────────────────────────────────────┤
│  后续扩展：                                     │
│  · DatamgrService → 跨设备分布式同步            │
│  · cloudData → 华为云空间端云同步               │
└─────────────────────────────────────────────┘
```



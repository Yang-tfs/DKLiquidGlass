# DKLiquidGlass

[![build](https://github.com/Yang-tfs/DKLiquidGlass/actions/workflows/build.yml/badge.svg)](https://github.com/Yang-tfs/DKLiquidGlass/actions/workflows/build.yml)

iOS 16+ 的悬浮液态玻璃底栏。**一套代码，两条渲染路径**：

- **iOS 26 及以上** — 走系统 `UIGlassEffect`，拿到原生材质、边缘折射与触摸 flex
- **iOS 16 / 17 / 18** — 用系统模糊 + 自绘边缘装饰降级，观感约 **85%**

调用方只认 `DKGlassSurface` 一个类，不需要判断系统版本。

> **当前状态**：编译链路已跑通——GitHub Actions 在 `macos-latest` 上通过 `arm64` + `arm64e` 双架构构建，产出 `rootless` 与 `rootful` 两个 deb。**但还没有上真机**，材质的视觉效果与触感未经校准。调参记录见 [docs/design.md](docs/design.md)。

---

## 为什么会有这个项目

iOS 26 的 Liquid Glass 是目前唯一能做出「真玻璃」的路径，但它只存在于 iOS 26+。而大量设备停在 iOS 16——不是每个人都能换机。

把 iOS 26 的玻璃拆成七层之后，结论是：**六层可以在 iOS 16 上手搓出来，只有一层做不出**。

| 层 | iOS 26 | iOS 16 | 判定 |
|---|---|---|---|
| 背景模糊 | 系统渲染器 | `UIBlurEffect` | 可调 |
| 亮度 / 饱和响应 | 内置 | 叠加层 + 可选 `CAFilter` | 可调 |
| 自适应染色 | `tintColor` | 自算 | 可做 |
| 连续圆角 squircle | `UICornerConfiguration` | `cornerCurve` | **逐像素一致** |
| 边缘高光 + 内壁暗环 | 内置 | `CAGradientLayer` 描边遮罩 | 可做 |
| 边缘折射 lensing | 内置 | — | **做不出** |
| 触摸 flex | `interactive` | 位移 + 柔光斑 | 仅近似 |

做不出的那一层，原因是物理性的：折射需要"背后内容的像素"作为输入，而 `UIVisualEffectView` 的模糊由 WindowServer 在合成阶段完成——**视图里根本没有那份像素**。这张表是项目全部取舍的依据，详见 [docs/design.md](docs/design.md)。

好消息是：玻璃的「体积感」有约 70% 来自边缘处理，而不是模糊。所以第 5 层（顶边高光 + 内壁暗环）是投入产出比最高的一步，而且它用纯公开 API 实现。

---

## 结构

```
Sources/
├── DKGlass/
│   ├── DKGlassSurface.{h,m}   玻璃本体。版本分叉全部收在这里
│   ├── DKGlassTuning.{h,m}    所有需要上机校准的数字
│   └── DKGlassInk.{h,m}       内容极性判定与可读性配色
├── TabBar/
│   └── DKFloatingTabBar.{h,m} 悬浮胶囊 + 独立圆键，零宿主依赖
└── Preview/
    └── DKPreviewHook.xm       SpringBoard 演示入口（只为验证材质）
```

两个设计决策值得说明：

**1. 版本分叉只在一个文件里。**
`@available` 与私有 API 探测全部收在 `DKGlassSurface.m`。将来 iOS 27 换了材质 API，改动也只落在这一个文件，`DKFloatingTabBar` 一行都不用动。

**2. 私有 API 默认关闭。**
`CAFilter` 能再抠出一点饱和度，但它在 iOS 16.3.1 上的实际可用性未经验证。所以 `DKGlassInjectFilters` 默认为 `NO`——默认路径零私有 API，观感靠叠加层实现。想要那 5% 再打开。

---

## 构建

需要 macOS + [Theos](https://github.com/theos/theos) + Xcode。

```bash
export THEOS=~/theos

# iPhoneOS SDK 16.0 及以上即可，不需要 iOS 26 SDK
make package THEOS_PACKAGE_SCHEME=rootless
```

产物在 `packages/`。安装后 respring，桌面底部会出现一条演示底栏。

`Makefile` 里的 `TARGET` 是 `iphone:clang:latest:16.0`——**用 iOS 16 SDK 也能编译**，因为 iOS 26 的 `UIGlassEffect` 走的是运行时反射而不是编译期符号。这一点与上游 DYKiller 不同（后者强制要求 iOS 26+ SDK）。

### 打包方案

| 越狱环境 | 命令 |
|---|---|
| Dopamine / palera1n rootless | `make package THEOS_PACKAGE_SCHEME=rootless` |
| 传统 rootful | `make package` |
| roothide Bootstrap | `make package THEOS_PACKAGE_SCHEME=roothide` |

### 没有 macOS？用 GitHub Actions

仓库自带 [`.github/workflows/build.yml`](.github/workflows/build.yml)。推代码或手动触发后，会在 `macos-latest` 上自动编译 `rootless` 与 `rootful` 两个版本，产物在 Actions 页面的 Artifacts 里下载。

这意味着**不装 Theos 也能验证代码是否能编过**——改完 push，等两分钟看结果。

---

## 巨魔（TrollStore）用户看这里

**巨魔不是越狱。** 那里没有 MobileSubstrate，deb 里的 tweak 根本不会被加载——装了也不会显示任何东西。这是环境限制，不是 bug。

本项目为此提供第二个产物：**`DKLiquidGlass-TrollFools-dylib`**，一个不含任何 substrate 依赖的纯 dylib（`library.mk` 编译，`Sources/Preview` 被排除在外，因为那里的 `%hook` 会引入 substrate 运行时依赖）。

### 用法

1. 从 Actions 的 Artifacts 下载 `DKLiquidGlass-TrollFools-dylib`，解压得到 `DKLiquidGlassInject.dylib`
2. 用 **TrollFools** 把它注入到抖音
3. 重新打开抖音

底栏会在 App 激活后 1 秒自动挂到窗口底部，**可以拖动**——因为它默认会和抖音自己的底栏叠在一起，需要挪开看。

### 这一版能做什么、不能做什么

| 能 | 不能 |
|---|---|
| 看到玻璃材质的真实观感 | 切页（拿不到抖音的 tab 控制器） |
| 拖动、点击、触摸反馈 | 隐藏抖音原生底栏 |
| 在 Console 里看能力与参数 | 读取抖音的选中态来同步 |

原因：`Sources/Host/DKHostAttach.m` 只用公开 API（`connectedScenes` / `keyWindow` / 通知），**不 hook 任何抖音的类**。好处是对抖音版本完全免疫，抖音怎么改类名都不影响；代价是拿不到它内部的 tab 状态。

要真正接管底栏，得按 `docs/design.md` §7 的思路去 hook `AWENormalModeTabBar`，那是一步大跨度的改动。

### 排查

注入后没反应，在 Console（macOS 上的「控制台」app，选中设备）里搜 `DKLiquidGlass`：

```
[DKLiquidGlass] 已挂载 · com.ss.iphone.ugc.Aweme · glass=fallback · rim=0.50/0.05 ...
```

- **看到这行但屏幕没变化** → 底栏挂上了但被抖音的原生底栏盖住，或者位置在屏幕外，试试拖动
- **完全没这行** → dylib 没被加载。检查 TrollFools 是否注入成功；抖音有完整性校验，注入后可能被它检测并拒绝启动
- **`glass=native(iOS26)`** → 只有在 iOS 26 设备上才会出现，你是 16.3.1，应该是 `fallback`

---

## 调参

**所有需要上机二分校准的数字都在 `DKGlassTuning.m`**。调材质观感不需要碰任何逻辑代码。

```bash
# 改完直接重装，respring 看效果
make package THEOS_PACKAGE_SCHEME=rootless && make install
```

`DKGlassSurface.capabilitySummary` 会打印当前的能力与参数快照，装好后在 Console 里搜 `DKLiquidGlass` 就能看到：

```
[DKLiquidGlass] preview installed · glass=fallback · rim=0.50/0.05 hairline=0.14 shadow=0.42 · filters=off · blur=+18 sat=1.90 lift=+0.06
```

### 校准方法

不要凭感觉调。**找一台 iOS 26 设备放在旁边并排比对**，同一张壁纸、同一角度，逐项二分：

1. 先固定边缘装饰（第 5 层），它是最确定的一层——参数已经接近参考值
2. 再调 `DKGlassBrightnessLift`，这是"玻璃亮起来"的主要来源
3. 最后才动 `DKGlassSaturationBoost`（需要先开 `DKGlassInjectFilters`）

每一项改了都记一笔，`docs/design.md` 有一张校准记录表可以填。

---

## 接入宿主

`DKFloatingTabBar` 不依赖任何 App 的类。接入时只需要：

```objc
DKFloatingTabBar *bar = [[DKFloatingTabBar alloc] initWithFrame:CGRectZero];
bar.items = @[
    [DKFloatingTabItem itemWithImage:img1 selectedImage:sel1 title:nil],
    ...
];
bar.delegate = self;       // 点击回调里自己切页
bar.material = DKGlassMaterialRegular;
bar.polarity = DKGlassPolarityDark;

CGSize size = [bar preferredSizeForWidth:window.bounds.size.width];
bar.frame = CGRectMake(0, window.bounds.size.height - size.height - 34, size.width, size.height);
[window addSubview:bar];
```

一个来自上游 DYKiller 的教训，接入时务必注意：

> 切页必须走宿主自己的按钮点击回调。直接写 `selectedIndex` 会被宿主的 override 吞掉——底栏选中态变了、宿主的 selectedIndex 仍是 0、页面也没换，只是「看着切了」。

所以 `selectedIndex` 在本项目里只负责**显示**，真正的切页由 delegate 回调交给宿主完成。

---

## 致谢与来源

本项目的技术路线来自对 [DYKiller](https://github.com/HierarchThurs/DYKiller)（MIT）的源码分析，特别是：

- 内容极性判据（读宿主文字色反推底色，而不是读外观模式）
- 未选中浓度取 60% 而非 50% 的对比度依据
- 「切页必须走宿主回调」的实测结论

本项目是独立实现，不复用其代码，也不包含任何针对特定 App 的 hook。

---

## 已知限制

- **没有上真机。** 代码能编过、能打包、能签名，但材质观感、几何对齐、触摸反馈都还没有在设备上验证过。第一次装上大概率要调 `DKGlassTuning.m` 里的数字。
- **边缘折射不可实现。** 见上文，这是物理限制不是工程量问题。
- **动效会比 iOS 26 露馅。** 静态观感接近，滚动和切页时缺少材质流动。

## 许可

MIT，见 [LICENSE](LICENSE)。

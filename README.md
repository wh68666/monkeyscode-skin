# MonkeyCode Skin

给 MonkeyCode 桌面版（Tauri/WebView2）换肤的 MVP 工具。原理与 [Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 一致：**不修改官方安装包**，通过本机 CDP（Chrome DevTools Protocol）向渲染进程注入主题。

## 目录结构

```
MonkeyCodeSkin\
├─ skin-lib.ps1         共享库：CDP 客户端、应用启停、主题包加载、注入脚本生成
├─ MonkeyCodeSkin.exe          托盘应用（双击即用）
├─ MonkeyCodeSkin.app.ps1      托盘应用源码（与 exe 等效）
├─ app\                        构建：build.ps1（ps2exe 打包）、app.ico
├─ skin-start.ps1       启动器：自动导入 imports\ 下的 zip → 关闭现有实例 → 带调试端口重启 → 拉起注入器
├─ skin-injector.ps1    注入器：向所有页面目标推送主题，监听新窗口，应用退出时自动结束
├─ skin-import.ps1      导入器：Codex Dream Skin 主题包 zip -> themes\<id>\
├─ skin-clear.ps1       恢复：关闭并正常重启 MonkeyCode（无调试端口、无皮肤）
├─ themes\aurora\       示例主题包（极光渐变 + 暗色玻璃）
│   ├─ theme.json       元数据与壁纸参数（surfaceOpacity / blurPx / fit）
│   ├─ theme.css        附加 CSS（调色板覆盖、标题栏软化、底部压暗）
│   └─ background.jpg   壁纸（1920x1080，程序化生成，无版权问题）
└─ logs\                运行日志
```

## 安装与分发（发给其他用户）

发布包：仓库根目录 `build-release.ps1` 一键产出 `release\MonkeyCodeSkin-v<版本>.zip`，
内含 `MonkeyCodeSkin.exe` + `skin-lib.ps1` + 本 README。**exe 必须与 skin-lib.ps1 同目录**（运行时读取）。

1. 解压到一个有写权限的独立目录（如 `D:\MonkeyCodeSkin`），首次运行会在旁边生成
   config.json / themes\ / logs\ / assets\，这些是用户数据，升级时不要删
2. 双击 `MonkeyCodeSkin.exe`。需本机已安装 MonkeyCode 官方桌面版（默认路径 `D:\MonkeyCode`）
3. 首次运行若 Windows 弹“已保护你的电脑”：点 **更多信息 → 仍要运行**；或右键 exe →
   属性 → 勾选 **解除锁定** 后再运行。ps2exe 封装的 exe 可能被个别杀软误报；
   介意可直接运行 MonkeyCodeSkin.app.ps1（效果相同）
4. 升级新版本：用新 zip 覆盖 `MonkeyCodeSkin.exe` 和 `skin-lib.ps1` 两个文件即可，
   配置与已装主题自动保留

## MonkeyCodeSkin.exe（托盘应用，推荐）

```
MonkeyCodeSkin.exe   双击启动，常驻托盘；主窗口含两个标签页
```

- **跑马灯公告**：主窗口顶部滚动显示微云分享笔记的内容（share.weiyun.com/8ptg57V2，
  微云里改内容即生效）；启动时在线拉取，失败回退到 logs\announcement.txt 缓存，之后每 30 分钟自动刷新
- **语言切换**：右上角下拉框 English / 简体中文 / 繁體中文，切换后全界面（页签、按钮、
  状态栏、托盘菜单、删除确认弹窗）立即更新；选择保存在 config.json 的 lang 字段，首次启动按系统语言自动选择
- **My Themes**：已装主题列表（双击或点 Apply 应用，会自动重启 MonkeyCode 并注入）；
  拖拽 zip 到列表或点 Import zip... 导入；选中主题后点 Delete theme 删除主题包
  （弹窗确认，删除使用中的主题会同时清除皮肤记录）；Official look 恢复官方外观
- **Repository (Remote)**（中文页签：主题仓库）：内置远程图库浏览器（api.dreamskin.cc，600+ 主题），
  主题名后以太阳/月亮小图标标注 light / dark 外观；双击或点 Download and install selected
  直接下载安装，Load more 加载更多，也可点 Open in browser 去网页看预览
- **托盘图标**：左键双击打开主窗口；右键菜单直接切换已装主题 / 恢复官方外观 / 退出
- 应用本身即注入器（常驻期间自动给新开的 MonkeyCode 窗口补注入）；
  当前主题记录在 config.json，重启 exe 后若 MonkeyCode 已带调试端口运行则自动接管
- 若 MonkeyCode 正在运行，切换主题会先关闭它再带调试端口重启（会话内未保存的输入会丢失）
- 重新构建：`powershell -File app\build.ps1`（需网络安装 ps2exe 模块）
- exe 为 ps2exe 封装，个别杀软可能误报；介意可直接运行 MonkeyCodeSkin.app.ps1（效果相同）

## 使用方法（脚本模式）

```powershell
```powershell
# 换肤（会自动重启 MonkeyCode；-Force 跳过确认）
powershell -NoProfile -ExecutionPolicy Bypass -File skin-start.ps1 -Theme aurora -Force

# 恢复官方外观
powershell -NoProfile -ExecutionPolicy Bypass -File skin-clear.ps1
```

要求：Windows PowerShell 5.1（系统自带）、MonkeyCode 安装于 `D:\MonkeyCode`（可用 `-AppExe` 指定其他路径）。

## 直接使用 Codex Dream Skin 主题包（已实测）

从 dreamskin.cc 等渠道下载的 Codex 主题包（zip）可以零改动使用，两种方式任选：

```powershell
# 方式一：手动导入后换肤
powershell -NoProfile -ExecutionPolicy Bypass -File skin-import.ps1 -Zip C:\path\to\theme.zip

# 方式二：把 zip 丢进 imports\ 文件夹，skin-start 会自动导入（处理完移入 imports\done\）
#   C:\Users\A\MonkeyCodeSkin\imports\xxx-0.1.0.zip  ->  themes\<主题id>\
powershell -NoProfile -ExecutionPolicy Bypass -File skin-start.ps1 -Theme <主题id> -Force
```

导入器兼容 Dream Skin v1 契约（zip ≤32MiB / ≤32 条目 / 解压后 ≤64MiB），带 manifest.json
的包会逐文件校验 SHA-256；也兼容无 manifest 的简化包。文件在 zip 根目录或单一子目录均可。

导入时的字段映射：

| Codex 主题包 | MonkeyCode 主题 |
|---|---|
| `image` 背景图 | `background.<ext>` 壁纸 |
| `art.focusX/focusY` | `position: "X% Y%"` 背景定位 |
| `colors.panel` 的 alpha（如 `#1e1e1e55`） | `surfaceOpacity: 0.33`（作者透明度意图） |
| `colors.*` 九个色板 token | `--color-base-100/200/300`、`--color-primary` 等 daisyUI 变量 |
| `theme.css`（选择器面向 Codex DOM） | 存为 `codex-extra.css` 备查，不注入 |
| `manifest.json` 许可证/作者 | 写入 `theme.json` 的 `imported` 字段 |

## 工作原理（全部经过实测验证）

1. WebView2 加载器读取环境变量 `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9223`，
   零修改打开 CDP 调试端口（会话级，仅作用于该次启动的实例）
2. 注入器通过 `http://127.0.0.1:9223/json` 枚举页面目标（主窗口 + 桌宠窗口），
   经 WebSocket 附加后执行注入脚本，并用 `Page.addScriptToEvaluateOnNewDocument`
   注册持久化注入（每次新文档自动重挂）
3. 注入脚本**复用 MonkeyCode 官方壁纸机制**：设置 `data-mc-background=active` 属性，
   变量（`--mc-background-image/surface-opacity` 等）通过注入的 `<style>` 以
   `!important` 写入——样式表 `!important` 优先级高于应用偏好系统回写的非重要内联变量，
   保证皮肤不会被应用覆盖

## 应用时自动调教（reference tuning）

以实测满意的参考主题 cecilylove002 为基准：应用任何主题（内置 / 导入 / 图库下载）时，
注入器在运行时统一做以下处理，**主题包文件本身不做任何修改**：

- 面板透明度强制 50%（`--mc-surface-opacity:50% !important`），壁纸透过面板清晰可见
- 壁纸模糊 0、fit=cover；背景定位仍使用主题包自己的 position
- 主题包 CSS 未绘制壁纸层（`.mc-workbench-background`）时，自动追加参考配方：
  主题底色 25% 压暗 + saturate(0.9)，壁纸保持画面主体
- 配方以**普通声明直接绘制 data-URI**，不经过自定义属性（原因见关键坑第 4 条）
- 已自带壁纸处理的主题（aurora / cecilylove002）不会被二次覆盖
- 参数可在 skin-lib.ps1 的 `$script:MC_TUNING` 中调整

## 关键坑（调试记录）

- 应用偏好系统会重写 html 上的内联 CSS 变量（把 surface-opacity 改回 100%），
  必须用样式表 `!important` 压制
- 应用带 single-instance 插件：换肤启动前必须完全退出（脚本已处理，
  含清理持有 EBWebView 锁的 msedgewebview2 进程）
- 点关闭按钮是最小化到托盘，`CloseMainWindow` 无效，需强制结束
- Chromium 对 CSS 自定义属性值有 2^21（2,097,152）字符上限（实测 2,000,000 可用、
  2,100,000 被丢）：大壁纸（PNG 常超 2MB）的 data-URI 放进 `var(--mc-background-image)`
  会被解析器静默丢弃，普通声明 `background-image:url(...)` 无此限制——参考调教因此直接绘制壁纸层

## 安全说明

- 不修改官方二进制与签名，应用更新后重新执行 skin-start 即可
- 调试端口绑定 127.0.0.1 但**无鉴权**，同机其他进程可连接；不用皮肤时执行
  skin-clear 或正常重启即可关闭端口
- 注入内容仅为 CSS 与设置属性的 JS，不涉及网络与数据读取

## 主题包格式

```
themes/<name>/
├─ theme.json     必需：id / version / surfaceOpacity(0~1) / blurPx / fit(cover|contain)
├─ theme.css      可选：附加 CSS（注入为 #mc-skin-style）
└─ background.jpg 支持 .jpg/.jpeg/.png/.webp，以 data-URI 内嵌注入
```

## 已知限制与路线图

- [x] MVP：启动器 + 注入器 + 示例主题
- [x] Codex Dream Skin 主题包导入（manifest 校验 + token 映射 + imports\ 自动导入）
- [x] MonkeyCodeSkin.exe：托盘常驻 + UI + 图库在线安装 + 一键切换
- [x] 启动时检查 GitHub Release 更新并提示（托盘气泡，点击打开下载页）
- [ ] 持久化通道：MonkeyCode 自带 `mc.theme="mc-custom"` + `mc.themeCustomCss`
      自定义主题机制（localStorage，官方每次启动自动应用），可把主题包写入其中，
      实现免注入器持久换肤；亦可探测应用内置的壁纸资产存储（`background_read` 命令）
- [ ] Safe CSS 白名单 + 选择器 doctor（对抗应用更新导致的 DOM 漂移；
      Codex 包的 theme.css 因面向 Codex DOM 暂不注入）
- [ ] 桌宠窗口（pet.html）暂只应用调色板，壁纸层不存在于该页面

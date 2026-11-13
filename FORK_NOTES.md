# Fork 说明

## 代码出处

本项目基于 **Boring Notch** 修改而来：

- 原始项目：<https://github.com/TheBoredTeam/boring.notch>
- 原始作者：TheBoredTeam 及 Boring Notch 贡献者
- 许可证：GNU General Public License v3.0（见仓库根目录 `LICENSE`）

本仓库是上述项目的个人 Fork，保留原始版权与许可证声明。除以下列出的改动外，
其余代码均来自原始项目。

## 本 Fork 的改动

### 1. 中英文切换与本地化补全

- 增加中文 / English 界面语言切换。
- 补齐设置页、启动引导、音乐控制、文件架、日历、HUD、XPC 授权等界面的
  `zh-Hans` 翻译，切换语言后各页面保持一致。

### 2. 启动与辅助功能授权体验

- 调整辅助功能授权检测逻辑，避免每次启动重复弹出授权提示。
- 修复已授权但界面仍提示未授权、HUD 功能无法开启的问题。
- 优化授权后的启动流程，避免授权完成后应用退出或重复拉起。

### 3. 刘海展开布局

- 展开后的刘海尺寸固定为 **400pt × 220pt**。
- 移除外观设置中的展开宽度、展开高度调节及预览控件。
- 修复音乐播放器在展开刘海中被裁切的问题，确保专辑封面、歌曲信息、
  进度条以及播放控制按钮完整显示。
- 播放器内容在可用高度内自适应分布，减少底部无效留黑。

### 4. 顶部功能区

- 将「主页 / 文件存放」功能区图标整体左移，更贴近刘海左侧。

### 5. 构建与安装

- 增加本地 Release 构建的 `Configuration/sign_app.sh` 签名脚本。
- 调整应用重新启动相关逻辑，便于本地构建、安装与调试。

## 构建

```bash
xcodebuild -scheme boringNotch -configuration Release -destination 'platform=macOS' build
```


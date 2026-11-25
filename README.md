# 三角洲行动 · 地图自动下载开关

> 用 Windows 防火墙拦住游戏自带的下载引擎，**一键禁止《三角洲行动》在后台自动下载你根本不玩的地图包，同时堵掉它的 P2P 偷偷上传**；想更新时一键解禁，系统里不留痕迹。

A single-file portable `.bat` that blocks Delta Force (国服/腾讯启动器版) map auto-download and P2P upload using Windows Firewall rules. One click to block, one click to restore. No game files are touched.

---

## 这是解决什么问题的

《三角洲行动》每次启动、进大厅，都会在后台用 **TinyDL / TenioDL** 这类下载引擎自动拉取地图包——包括你压根不玩的地图，几十 GB 的流量和磁盘说没就没。而且它用的是 P2P，**已经下好的资源还会持续上传给别人**，挂机时也在跑流量。

游戏设置里没有"不要自动下载"的开关。社区里的办法是在「防火墙 → 高级设置 → 出站规则」里手动给 `TinyDL.exe` 建一条"阻止连接"规则，想下载时再去禁用规则——但每次都要点七八层菜单，还容易选错文件。

这个脚本就是把那套手动操作做成两条命令，并且**自动找出所有相关的下载引擎 exe**（不同客户端版本名字、路径都不一样）：

| 组件 | 作用 |
| --- | --- |
| `TinyDL.exe` / `TinyDL64.exe` | 新版下载引擎，启动器、游戏本体、WeGame 目录里可能各有一份 |
| `TenioDL.exe` | 腾讯老的下载 / P2P 引擎 |
| `DeltaDL.exe` 之类变体 | 换版本时冒出来的同类引擎 |

## 效果

- ✅ 游戏照常启动、照常登录、照常联机打**已下载**的地图
- 🚫 不再自动下载新地图包，也不再上传（出站 + 入站双向拦截）
- ↩️ 想恢复：一键删除规则，防火墙里干干净净
- 📍 每次运行都会把**扫描到的游戏安装位置和每个组件完整路径**打印出来，拦了谁一目了然

## 快速开始

1. 到 [Releases](../../releases) 下载 `delta-force-map-download-switch-2.0.1.bat`（**单文件，就是全部**）；
2. 双击它 → 只弹一次 UAC，点「是」（建防火墙规则必须要管理员权限）；
3. 菜单选 `1` 禁止下载，选 `3` 看状态，选 `2` 恢复。

界面长这样：

```
============================================================
  当前状态
============================================================
  游戏安装位置（自动扫描）：
    E:\Delta Force

  下载组件（扫描到的文件位置）：
    E:\Delta Force\Delta Force\WeGameLauncher\tinydl\TinyDL.exe
    E:\Delta Force\launcher\TinyDL.exe
    E:\Delta Force\launcher\WeGameLauncher\TenioDL\TenioDL.exe

  拦截规则：
    [出站] 已生效   E:\Delta Force\launcher\TinyDL.exe
    [入站] 已生效   E:\Delta Force\launcher\TinyDL.exe
    ...

  结论：地图自动下载已禁止（同时阻止了 P2P 上传）。
```

也支持命令行（方便写教程或做快捷方式）：

```bat
三角洲地图下载开关-单文件版.bat -Mode status    :: 查看状态
三角洲地图下载开关-单文件版.bat -Mode off       :: 禁止下载（需管理员）
三角洲地图下载开关-单文件版.bat -Mode on        :: 恢复下载（需管理员）
```

## 什么时候要先选「2 恢复」

- 游戏大版本更新、新赛季、要下新地图时（拦截状态下启动器可能提示更新失败）
- 你想玩某张还没下载的地图时
- 排查「进游戏黑屏 / 提示资源缺失」时——那是地图包没下载，不是脚本搞坏的

平时玩已下载的地图，一直保持「1 禁止」就行。

## 它到底做了什么

**识别下载引擎**（不写死路径，换盘 / 重装 / 换电脑都不用改）：

1. 磁盘根目录下名字含 `Delta` / `三角洲` / `WeGame` / `Tencent` / `腾讯` / `Game` 的文件夹；
2. 已知相对路径 `Delta Force\launcher`、`Delta Force\Delta Force\WeGameLauncher`；
3. 注册表 `Uninstall` 里 DisplayName 匹配 `三角洲` / `Delta Force` 的安装目录；
4. 以上目录里按文件名前缀 `^(TinyDL|TenioDL|DeltaDL|tinyget)` 递归匹配 `.exe`；
5. 再加上 `tinydl`、`TenioDL` 这两个专用子目录里的**任意** `.exe`（防游戏更新把进程改名放进原目录、漏网）；
6. 都没找到才全盘兜底扫描。

**建规则**：对每个 exe 各建一条出站 + 一条入站 `Block` 规则，名字 `DF-NoMapDL-OUT-<n>` / `DF-NoMapDL-IN-<n>`，分组 `DeltaForce-NoMapDownload`，对「域 / 专用 / 公用」三种网络配置文件都生效。删的时候只按 `DF-NoMapDL-*` 通配删，**绝不动你自己其它的防火墙规则**。

## 安全性

- 单文件版 = 一个纯文本 `.bat`，里面那段乱码是 base64 编码的 PowerShell 脚本原文，不是加壳的二进制；
- 运行时它把 base64 解回脚本，临时存到 `%TEMP%\DF-MapDL\payload.ps1`，执行完**立刻删除**；
- 提权时申请的是微软签名的 `powershell.exe`，不是这个 bat 本身——所以全程只弹一次 UAC（直接提权未签名 bat 会多弹一个「无法验证发布者」的警告）；
- 不联网、不写注册表、不装服务、不驻留后台、不碰游戏文件、不注入进程；
- 想审计：用任意 base64 解码器把两段 `#==PS_BEGIN==` / `#==PS_END==` 之间的内容解出来，逐行看。

## 仓库结构

```
三角洲地图下载开关-单文件版.bat   构建产物：分享/下载就这一个文件
使用说明.txt                      面向普通用户的中文说明
源码/
  DeltaForce-MapDownload.ps1      真正的 PowerShell 源码，中文注释
  三角洲地图下载开关.bat          调试启动器：直接跑上面的 ps1（改代码时用）
  重新生成-单文件版.ps1           改完 ps1 后跑它，重新打包出单文件版 bat
```

重新打包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "源码\重新生成-单文件版.ps1"
```

它会自动补 UTF-8 BOM（PowerShell 5.1 解析中文必须）并把 ps1 压成纯 ASCII 的 bat。bat 里只有 ASCII、中文全在 base64 内，所以不会出现乱码问题。

## 常见问题

**会被封号吗？**
不会。这只是系统防火墙拦某个 exe 的外网连接，不碰游戏文件、不改内存、不注入、不改客户端，和杀毒软件拦程序的原理一模一样，属于系统层面的网络限制，不是外挂行为。

**为什么我这儿只显示 3 个组件，别人的截图有 4 个？**
不同客户端版本（国服启动器版 / WeGame 版 / Steam 版 / 不同赛季）打包结构不一样，`TinyDL64.exe`、`E:\Delta Force\WeGame\tinydl\` 这类路径在部分版本存在、部分不存在。脚本按文件名前缀 + 目录双保险扫，**存在几个就拦几个**，不用手动加。

**换了盘 / 重装系统 / 换了台电脑？**
重装系统规则会没（规则在系统里），但脚本每次运行都重新扫描，双击选 `1` 即可。换盘、换目录也不用改脚本。

**公司/学校电脑提示拿不到管理员权限？**
组策略可能禁止修改防火墙，那种环境只能手动在防火墙里操作。

**只测过什么环境？**
Windows 11 26xxx + Windows PowerShell 5.1 + 国服（腾讯启动器版）客户端。Windows 10 理论上一致（用的都是 `New-NetFirewallRule` / `Get-NetFirewallRule`）。Steam 版另有官方地图 DLC 分包机制，与本脚本针对的布局不同。

## 免责声明

本项目与腾讯 / 天美 / Team Jade / 三角洲行动官方无任何关系，未使用其任何代码或资源。脚本只操作本机 Windows 防火墙规则，不修改游戏文件。请自行承担使用风险；如游戏更新后行为变化，欢迎提 Issue。

## License

[MIT](LICENSE)

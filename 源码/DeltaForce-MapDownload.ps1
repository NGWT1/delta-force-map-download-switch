#Requires -Version 5.1
<#
    三角洲行动 · 地图自动下载开关（便携版 / 单文件逻辑）

    原理
    ----
    游戏的地图包自动下载（以及被吐槽的 P2P 偷跑流量上传）由下面这几个进程负责：
        TinyDL.exe          新版下载引擎（启动器一份、游戏本体一份）
        TenioDL.exe         腾讯老的下载 / P2P 引擎
    本脚本用 Windows Defender 防火墙，对这些 exe 建「出站 + 入站」阻止规则，
    游戏照常启动、照常联机，只是没法再自动拉地图包，也不再偷偷上传。
    想恢复时删除规则即可，系统里不留任何痕迹。

    用法
    ----
    双击同目录下的 三角洲地图下载开关.bat（会自动请求管理员权限）。
    也可以：powershell -ExecutionPolicy Bypass -File 本文件 -Mode off|on|status
#>

[CmdletBinding()]
param(
    [ValidateSet('menu', 'off', 'on', 'status')]
    [string]$Mode = 'menu'
)

$ErrorActionPreference = 'Stop'

$RulePrefix      = 'DF-NoMapDL'          # 规则名统一前缀，删改都只碰这一族
$RuleGroup       = 'DeltaForce-NoMapDownload'
$ScriptName      = '三角洲行动 · 地图自动下载开关'
# 下载组件按「文件名开头」匹配：TinyDL.exe / TinyDL64.exe / TenioDL.exe / DeltaDL.exe …
# （不同版本的国服客户端文件名不完全一样，所以用前缀而不是写死全名）
$DownloaderPattern = '^(TinyDL|TenioDL|DeltaDL|tinyget)'

$script:DetectedRoots = @()   # 本次扫描认定的游戏安装位置

# ---------------------------------------------------------------- 基础工具

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ("  " + $Text) -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated {
    $argLine = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Mode {1}' -f $PSCommandPath, $Mode
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine | Out-Null
    } catch {
        Write-Host '  自动提权失败，请右键本脚本或 .bat，选择「以管理员身份运行」。' -ForegroundColor Red
    }
}

# ---------------------------------------------------------------- 定位组件

function Get-DownloaderPaths {
    $found = New-Object System.Collections.Generic.List[string]
    $add = {
        param([string]$p)
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return }
        $full = (Resolve-Path -LiteralPath $p).Path
        if (-not $found.Contains($full)) { [void]$found.Add($full) }
    }

    $drives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Free })
    $roots  = New-Object System.Collections.Generic.List[string]

    # ---- 第一层：已知的相对路径，几乎零耗时，覆盖绝大多数国服安装结构 ----
    $relPaths = @(
        'Delta Force\launcher\TinyDL.exe'
        'Delta Force\launcher\WeGameLauncher\TenioDL\TenioDL.exe'
        'Delta Force\Delta Force\WeGameLauncher\tinydl\TinyDL.exe'
        'DeltaForce\launcher\TinyDL.exe'
        'Delta Force\TinyDL.exe'
        'WeGameApps\Delta Force\launcher\TinyDL.exe'
    )
    foreach ($drv in $drives) {
        foreach ($rel in $relPaths) { & $add (Join-Path $drv.Root $rel) }
    }

    # 由命中路径反推游戏根目录（盘符 + 第一级目录），后面只扫这些目录，
    # 不去碰 C:\XboxGames 这类名字像游戏、实际无关的大目录
    foreach ($hit in @($found)) {
        $parts = $hit.Split('\')
        if ($parts.Count -ge 3) {
            $root = $parts[0] + '\' + $parts[1]
            if (-not $roots.Contains($root)) { [void]$roots.Add($root) }
        }
    }

    # ---- 第二层：注册表里登记的安装目录 ----
    if ($roots.Count -eq 0) {
        $regRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($key in $regRoots) {
            Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match '三角洲|Delta\s*Force' } |
                ForEach-Object {
                    $cands = @()
                    if ($_.InstallLocation) { $cands += $_.InstallLocation }
                    if ($_.DisplayIcon) {
                        $icon = ($_.DisplayIcon -replace ',\s*\d+\s*$', '').Trim('"')
                        if ($icon) { $cands += (Split-Path -Parent $icon) }
                    }
                    foreach ($c in $cands) {
                        if ($c -and (Test-Path -LiteralPath $c) -and -not $roots.Contains($c)) { [void]$roots.Add($c) }
                    }
                }
        }
    }

    # ---- 第三层：还是没定位到，才扫磁盘根目录下名字可疑的文件夹 ----
    if ($roots.Count -eq 0) {
        foreach ($drv in $drives) {
            Get-ChildItem -LiteralPath $drv.Root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'Delta|三角洲|WeGame|Tencent|腾讯|Games?$' } |
                ForEach-Object { [void]$roots.Add($_.FullName) }
        }
    }

    $script:DetectedRoots = @($roots | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)

    # 在定位到的目录里找：①按文件名前缀 ②引擎专用目录里的任何 exe
    $engineDirs = @('tinydl', 'TenioDL')
    foreach ($root in $script:DetectedRoots) {
        Get-ChildItem -LiteralPath $root -Recurse -Depth 6 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.exe' -and $_.Name -match $DownloaderPattern } |
            ForEach-Object { & $add $_.FullName }

        Get-ChildItem -LiteralPath $root -Recurse -Depth 6 -Directory -ErrorAction SilentlyContinue |
            Where-Object { $engineDirs -contains $_.Name } |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -File -Filter '*.exe' -ErrorAction SilentlyContinue |
                    ForEach-Object { & $add $_.FullName }
            }
    }

    # ---- 兜底：全盘按文件名找（很慢，只有前面都没命中才会走这里）----
    if ($found.Count -eq 0) {
        foreach ($drv in $drives) {
            Get-ChildItem -LiteralPath $drv.Root -Recurse -Depth 5 -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq '.exe' -and $_.Name -match $DownloaderPattern } |
                ForEach-Object { & $add $_.FullName }
        }
    }

    return @($found)
}

# ---------------------------------------------------------------- 规则操作

function Get-OurRules {
    return @(Get-NetFirewallRule -Name "$RulePrefix-*" -ErrorAction SilentlyContinue)
}

function Remove-OurRules {
    $rules = Get-OurRules
    if ($rules.Count -eq 0) { return 0 }
    Remove-NetFirewallRule -Name "$RulePrefix-*" -ErrorAction SilentlyContinue
    return $rules.Count
}

# ---------------------------------------------------------------- 状态显示

function Get-DisplayRoots {
    param([string[]]$Roots, [string[]]$Exes)

    if (-not $Roots -or $Roots.Count -eq 0) { return @() }
    if (-not $Exes -or $Exes.Count -eq 0) { return @($Roots) }

    # 只保留真正装着下载组件的目录
    $hit = @($Roots | Where-Object {
        $r = $_
        @($Exes | Where-Object { $_.StartsWith($r, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    })
    if ($hit.Count -eq 0) { return @() }

    # 去掉被别的命中目录包含的嵌套目录，只留最外层
    return @($hit | Where-Object {
        $r = $_
        -not (@($hit | Where-Object {
            $_ -ne $r -and $r.StartsWith($_, [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0)
    })
}

function Show-Status {
    Write-Title '当前状态'

    $exes  = @(Get-DownloaderPaths)
    $rules = @(Get-OurRules)

    Write-Host '  游戏安装位置（自动扫描）：' -ForegroundColor Gray
    $showRoots = @(Get-DisplayRoots -Roots $script:DetectedRoots -Exes $exes)
    if ($showRoots.Count -eq 0) {
        Write-Host '    未定位到（没找到下载组件时无法判断装在哪）' -ForegroundColor Yellow
    } else {
        foreach ($r in $showRoots) { Write-Host ("    " + $r) -ForegroundColor Gray }
    }

    Write-Host ''
    Write-Host '  下载组件（扫描到的文件位置）：' -ForegroundColor Gray
    if ($exes.Count -eq 0) {
        Write-Host '    未在磁盘上找到 TinyDL / TenioDL 这类下载组件（游戏可能没装，或装在非常规目录）' -ForegroundColor Yellow
    } else {
        foreach ($e in $exes) { Write-Host ("    " + $e) -ForegroundColor Gray }
    }

    Write-Host ''
    if ($rules.Count -eq 0) {
        Write-Host '  拦截规则：未创建' -ForegroundColor Yellow
        Write-Host '  结论：地图仍会自动下载。' -ForegroundColor Yellow
    } else {
        $blocked = 0
        Write-Host '  拦截规则：' -ForegroundColor Gray
        foreach ($r in $rules) {
            $program = ''
            try { $program = ($r | Get-NetFirewallApplicationFilter).Program } catch { }
            $dirText = if ("$($r.Direction)" -eq 'Outbound') { '出站' } else { '入站' }
            if ("$($r.Enabled)" -eq 'True') {
                $blocked++
                Write-Host ("    [{0}] 已生效   {1}" -f $dirText, $program) -ForegroundColor Green
            } else {
                Write-Host ("    [{0}] 未启用   {1}" -f $dirText, $program) -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        if ($blocked -gt 0) {
            Write-Host '  结论：地图自动下载已禁止（同时阻止了 P2P 上传）。' -ForegroundColor Green
        } else {
            Write-Host '  结论：规则存在但未启用，地图仍会自动下载。' -ForegroundColor Yellow
        }
    }

    # 防火墙本身若被关掉，规则不起作用
    $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled })
    if ($profiles.Count -gt 0) {
        Write-Host ''
        Write-Host ('  [警告] 以下防火墙配置已关闭，规则不会生效：' + (($profiles | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------- 主操作

function Invoke-Block {
    if (-not (Test-Admin)) {
        Write-Host '  添加防火墙规则需要管理员权限，正在请求提权……' -ForegroundColor Yellow
        Invoke-Elevated
        return 1
    }

    Write-Title '禁止地图自动下载'

    $exes = @(Get-DownloaderPaths)
    $showRoots = @(Get-DisplayRoots -Roots $script:DetectedRoots -Exes $exes)
    if ($showRoots.Count -gt 0) {
        Write-Host '  游戏安装位置（自动扫描）：' -ForegroundColor Gray
        foreach ($r in $showRoots) { Write-Host ("    " + $r) -ForegroundColor Gray }
        Write-Host ''
    }
    if ($exes.Count -eq 0) {
        Write-Host '  没找到 TinyDL / TenioDL / TinyDL64 这类下载组件，无法定位。' -ForegroundColor Red
        Write-Host '  可以把游戏安装文件夹整个拖进本窗口再回车：' -ForegroundColor Yellow
        $manual = Read-Host '  游戏目录'
        if ($manual) {
            $manual = $manual.Trim().Trim('"')
            if (Test-Path -LiteralPath $manual) {
                $exes = @(Get-ChildItem -LiteralPath $manual -Recurse -Depth 8 -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.Extension -eq '.exe' -and $_.Name -match $DownloaderPattern } |
                          ForEach-Object { $_.FullName })
            }
        }
    }
    if ($exes.Count -eq 0) {
        Write-Host '  仍然没有找到，已放弃。' -ForegroundColor Red
        return 2
    }

    $removed = Remove-OurRules
    if ($removed -gt 0) { Write-Host ("  已清理旧规则 {0} 条。" -f $removed) -ForegroundColor DarkGray }

    $index = 0
    foreach ($exe in $exes) {
        $index++
        New-NetFirewallRule -Name "$RulePrefix-OUT-$index" `
            -DisplayName "三角洲行动 禁止地图下载 (出站 $index)" `
            -Group $RuleGroup -Direction Outbound -Program $exe `
            -Action Block -Profile Any -Enabled True `
            -Description '阻止下载组件自动下载/上传地图包（便携脚本创建，可随时删除）' | Out-Null

        New-NetFirewallRule -Name "$RulePrefix-IN-$index" `
            -DisplayName "三角洲行动 禁止地图下载 (入站 $index)" `
            -Group $RuleGroup -Direction Inbound -Program $exe `
            -Action Block -Profile Any -Enabled True `
            -Description '阻止下载组件自动下载/上传地图包（便携脚本创建，可随时删除）' | Out-Null

        Write-Host ("  [+] 已阻止：{0}" -f $exe) -ForegroundColor Green
    }

    Write-Host ''
    Write-Host ("  完成：{0} 个组件，共 {1} 条规则。" -f $exes.Count, ($exes.Count * 2)) -ForegroundColor Green
    Write-Host '  现在启动游戏不会再自动下载地图；进未下载过的地图会提示资源缺失，属正常。' -ForegroundColor Gray
    Write-Host '  游戏要大版本更新时，先选「2 恢复自动下载」，更新完再选「1」。' -ForegroundColor Gray
    return 0
}

function Invoke-Unblock {
    if (-not (Test-Admin)) {
        Write-Host '  删除防火墙规则需要管理员权限，正在请求提权……' -ForegroundColor Yellow
        Invoke-Elevated
        return 1
    }

    Write-Title '恢复自动下载'

    $removed = Remove-OurRules
    if ($removed -eq 0) {
        Write-Host '  没有找到本脚本创建的规则，当前本来就没有限制。' -ForegroundColor Yellow
    } else {
        Write-Host ("  已删除 {0} 条规则，地图自动下载与更新已恢复。" -f $removed) -ForegroundColor Green
    }
    return 0
}

# ---------------------------------------------------------------- 交互菜单

function Read-Choice {
    $value = Read-Host '  请输入序号'
    if ($null -eq $value) { return '' }
    return $value.Trim()
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Title $ScriptName
        Write-Host '  1  禁止自动下载地图（添加防火墙拦截规则）'
        Write-Host '  2  恢复自动下载（删除拦截规则，可正常更新）'
        Write-Host '  3  查看当前状态'
        Write-Host '  0  退出'
        Write-Host ''
        switch (Read-Choice) {
            '1' { Invoke-Block   | Out-Null; Read-Host '  按回车返回菜单' | Out-Null }
            '2' { Invoke-Unblock | Out-Null; Read-Host '  按回车返回菜单' | Out-Null }
            '3' { Show-Status;                Read-Host '  按回车返回菜单' | Out-Null }
            '0' { return }
            default { }
        }
    }
}

# ---------------------------------------------------------------- 控制台字体

function Set-ConsoleCjkFont {
    # 老式控制台（conhost，也就是双击 bat 时弹出来的那个蓝底窗口）默认字体是
    # Lucida Console，没有中文字形：conhost 会把每个汉字当 1 格来排版，而实际
    # 画出来的字形有 2 格宽，于是字和字就叠在一起（"叠字"）。
    # 换成带 GB 字符集的等宽字体（新宋体/NSimSun）后，conhost 才知道汉字占 2 格。
    # Windows Terminal 自己按字形算宽度，不受影响，所以那里直接跳过。
    if ($env:WT_SESSION) { return }
    if ($Host.Name -ne 'ConsoleHost') { return }
    if ($env:DF_MAPDL_NOFONT) { return }

    $csharp = @'
using System;
using System.Runtime.InteropServices;

public static class DshConsoleFont
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct COORD { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CONSOLE_FONT_INFOEX
    {
        public uint cbSize;
        public uint nFont;
        public COORD dwFontSize;
        public int FontFamily;
        public int FontWeight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string FaceName;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool GetCurrentConsoleFontEx(IntPtr hOut, bool bMax, ref CONSOLE_FONT_INFOEX info);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SetCurrentConsoleFontEx(IntPtr hOut, bool bMax, ref CONSOLE_FONT_INFOEX info);

    public static string CurrentFace()
    {
        IntPtr h = GetStdHandle(-11);
        var info = new CONSOLE_FONT_INFOEX();
        info.cbSize = (uint)Marshal.SizeOf(typeof(CONSOLE_FONT_INFOEX));
        if (!GetCurrentConsoleFontEx(h, false, ref info)) return null;
        return info.FaceName;
    }

    public static bool SetFace(string face, short height)
    {
        IntPtr h = GetStdHandle(-11);
        var info = new CONSOLE_FONT_INFOEX();
        info.cbSize = (uint)Marshal.SizeOf(typeof(CONSOLE_FONT_INFOEX));
        if (!GetCurrentConsoleFontEx(h, false, ref info)) return false;
        info.FaceName = face;
        info.dwFontSize.X = 0;          // 0 = 由字体高度自动算宽度
        info.dwFontSize.Y = height;
        info.FontFamily = 54;           // TMPF_FIXED_PITCH | TMPF_TRUETYPE
        info.FontWeight = 400;
        return SetCurrentConsoleFontEx(h, false, ref info);
    }
}
'@

    try { Add-Type -TypeDefinition $csharp -ErrorAction Stop } catch { return }

    try {
        $face = [DshConsoleFont]::CurrentFace()
        if ($face -and ($face -match 'SimSun|NSimSun|Gothic|MingLiU|Ming|YaHei|KaiTi|宋|雅黑|黑体')) { return }

        foreach ($candidate in @('NSimSun', 'SimSun', 'MS Gothic')) {
            if ([DshConsoleFont]::SetFace($candidate, 18)) {
                Clear-Host
                return
            }
        }
    } catch { }
}

# ---------------------------------------------------------------- 入口

Set-ConsoleCjkFont

switch ($Mode) {
    'menu'   { Show-Menu }
    'off'    { Invoke-Block   | Out-Null }
    'on'     { Invoke-Unblock | Out-Null }
    'status' { Show-Status }
}

# 命令行模式（off / on / status）自己跑完就返回，双击时窗口会一闪而过，
# 所以停一下；菜单模式本来就在循环里等用户按键，不用再加。
if ($Mode -ne 'menu' -and -not [Console]::IsInputRedirected) {
    Write-Host ''
    Read-Host '  按回车键关闭窗口' | Out-Null
}

# 单文件版：脚本本体是运行时解包到 %TEMP%\DF-MapDL 下的，提权后由父进程
# 收不了尾，所以这里自己把临时文件删掉。直接跑源码目录里的 ps1 时路径对不上，
# 自然跳过，不会误删源码。
$tempRoot = Join-Path $env:TEMP 'DF-MapDL'
if ($PSCommandPath -and $PSCommandPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
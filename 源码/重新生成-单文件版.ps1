# ============================================================
#  重新生成「三角洲地图下载开关-单文件版.bat」
#
#  用法：改完同目录的 DeltaForce-MapDownload.ps1 之后，
#        右键本文件 →「使用 PowerShell 运行」，或在本目录执行：
#        powershell -NoProfile -ExecutionPolicy Bypass -File .\重新生成-单文件版.ps1
#
#  原理：把 ps1 的原始字节（UTF-8 带 BOM）转成 base64，每 76 字符一行，
#        夹在 bat 的 PS_BEGIN / PS_END 标记之间，生成纯 ASCII 的自解包 bat。
# ============================================================
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1  = Join-Path $here 'DeltaForce-MapDownload.ps1'
$out  = Join-Path (Split-Path -Parent $here) '三角洲地图下载开关-单文件版.bat'

if (-not (Test-Path -LiteralPath $ps1)) { throw "找不到源文件：$ps1" }

$bytes = [IO.File]::ReadAllBytes($ps1)
if (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
    Write-Host '[!] 源 ps1 没有 UTF-8 BOM，中文可能在 PowerShell 5.1 下乱码。已自动补 BOM。'
    $bytes = [byte[]](0xEF,0xBB,0xBF) + $bytes
    [IO.File]::WriteAllBytes($ps1, $bytes)
}

$b64 = [Convert]::ToBase64String($bytes)
$lines = @()
for ($i = 0; $i -lt $b64.Length; $i += 76) {
    $lines += $b64.Substring($i, [Math]::Min(76, $b64.Length - $i))
}

$header = @'
@echo off
rem ============================================================
rem  Delta Force - Map auto-download switch (single-file portable)
rem  Version 2.0
rem
rem  What it does:
rem    Blocks the game download components (TinyDL.exe / TinyDL64.exe /
rem    TenioDL.exe ...) with Windows Firewall rules, outbound + inbound.
rem    The game still starts and plays; it just cannot fetch map packs
rem    or upload P2P traffic. Remove the rules anytime - nothing else
rem    is touched.
rem
rem  Usage:
rem    Double-click this file (it asks for administrator rights), then:
rem      1 = block auto download       2 = allow / restore
rem      3 = show status / scan result 0 = quit
rem
rem  This .bat carries the real PowerShell code as base64 below,
rem  unpacks it to %TEMP%\DF-MapDL and deletes it after the run.
rem
rem  Generated from the DeltaForce-MapDownload.ps1 in the source
rem  folder - do not edit the base64 by hand; rerun the generator
rem  script instead.
rem ============================================================
setlocal EnableExtensions
title DF-MapDL
set "SELFBAT=%~f0"

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights ...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop } catch { exit 1 }" >nul 2>&1
    if errorlevel 1 (
        echo.
        echo [!] Could not get administrator rights.
        echo     Right-click this file and choose "Run as administrator".
        pause
    )
    exit /b
)

set "TMPDIR=%TEMP%\DF-MapDL"
if not exist "%TMPDIR%" md "%TMPDIR%" >nul 2>&1
set "TMPPS=%TMPDIR%\payload.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:TMPPS; $s=[IO.File]::ReadAllText($env:SELFBAT); $m=[string]::Concat('#==PS_','BEGIN=='); $n=[string]::Concat('#==PS_','END=='); $i=$s.LastIndexOf($m); $j=$s.IndexOf($n, $i); if($i -lt 0 -or $j -lt $i){ Write-Host 'payload marker missing'; exit 9 }; $b=$s.Substring($i+$m.Length, $j-$i-$m.Length) -replace '\s',''; $r=$b.Length -band 3; if($r -gt 0){ $b=$b.Substring(0, $b.Length - $r) }; [IO.File]::WriteAllBytes($p, [Convert]::FromBase64String($b))"
if errorlevel 1 (
    echo.
    echo [!] Failed to unpack the embedded script.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%" %*

del /f /q "%TMPPS%" >nul 2>&1
echo.
pause
exit /b 0

rem #==PS_BEGIN==

'@

$footer = "`r`n#==PS_END==`r`n"
$content = $header + ($lines -join "`r`n") + "`r`n" + $footer
[IO.File]::WriteAllText($out, $content, [Text.Encoding]::ASCII)

$size = (Get-Item -LiteralPath $out).Length
Write-Host ''
Write-Host '已生成：'
Write-Host "  $out"
Write-Host "  大小 $size 字节，纯 ASCII，可单文件分享。"
Write-Host ''
Write-Host '双击它即可使用（会请求管理员权限）。'
Write-Host ''

# build.ps1 - build MonkeyCodeSkin.exe with ps2exe (run in PowerShell 5.1)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
Set-Location $root

# 1. icon
Add-Type -AssemblyName System.Drawing
$icoPath = Join-Path $scriptDir 'app.ico'
if (-not (Test-Path $icoPath)) {
    $bmp = New-Object System.Drawing.Bitmap(64, 64)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(64, 64)), [System.Drawing.Color]::FromArgb(255, 79, 172, 255), [System.Drawing.Color]::FromArgb(255, 130, 80, 255))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, 64, 64, 180, 180)
    $path.AddArc(0, 0, 64, 64, 0, 180)
    $g.FillPath($brush, $path)
    $g.DrawString('M', (New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, 12, 8)
    $g.Dispose()
    $ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $fs = [IO.File]::Create($icoPath)
    $ico.Save($fs)
    $fs.Dispose()
    'icon created: ' + $icoPath
}

# 2. ps2exe module
if (-not (Get-Module -ListAvailable ps2exe)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null } catch { }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module ps2exe -Scope CurrentUser -Force
    Import-Module ps2exe
} else {
    Import-Module ps2exe
}

# 3. compile
$out = Join-Path $root 'MonkeyCodeSkin.exe'
Invoke-ps2exe -inputFile (Join-Path $root 'MonkeyCodeSkin.app.ps1') -outputFile $out -noConsole -iconFile $icoPath -title 'MonkeyCodeSkin' -description 'MonkeyCode desktop skinning tray app' -version 0.2.0.0 | Out-Null
if (Test-Path $out) { 'BUILT: ' + $out + ' (' + [math]::Round((Get-Item $out).Length / 1KB) + ' KB)' } else { 'BUILD FAILED' }

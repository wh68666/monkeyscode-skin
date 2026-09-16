# build-release.ps1 - build the exe and pack a distributable release zip
# Output: release\MonkeyCodeSkin-v<version>.zip  (exe + skin-lib.ps1 + README.md)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# version lives in app source (single source of truth)
$src = Get-Content (Join-Path $root 'MonkeyCodeSkin.app.ps1') -Raw -Encoding UTF8
$v = if ($src -match '\$script:AppVersion\s*=\s*''([^'']+)''') { $Matches[1] } else { '1.0.0' }
'App version: ' + $v

# building requires the exe not to be locked
Stop-Process -Name MonkeyCodeSkin -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'app\build.ps1')
if (-not (Test-Path (Join-Path $root 'MonkeyCodeSkin.exe'))) { throw 'build failed' }

$relDir = Join-Path $root 'release'
$stage = Join-Path $relDir 'stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item $stage -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $root 'MonkeyCodeSkin.exe') $stage
Copy-Item (Join-Path $root 'skin-lib.ps1') $stage
Copy-Item (Join-Path $root 'README.md') $stage

$zip = Join-Path $relDir ('MonkeyCodeSkin-v' + $v + '.zip')
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item $stage -Recurse -Force
'RELEASE ZIP: ' + $zip

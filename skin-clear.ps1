# skin-clear.ps1 - restore MonkeyCode's official look (ASCII only, PS 5.1)
# Closes MonkeyCode (and the skin injector with it) and relaunches it normally,
# without the CDP environment variable.
param([string]$AppExe = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'skin-lib.ps1')

if (-not $AppExe) { $AppExe = $script:MC_EXE_DEFAULT }
$log = Join-Path $PSScriptRoot 'logs\clear.log'
Write-McLog -Path $log -Message "=== skin-clear: restoring official look ==="

[void](Stop-MonkeyApp)
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $null
Start-Process -FilePath $AppExe -WorkingDirectory (Split-Path $AppExe)
Write-McLog -Path $log -Message "App relaunched normally (no CDP, no skin)."

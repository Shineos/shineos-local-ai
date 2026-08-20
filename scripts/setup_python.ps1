# setup_python.ps1 - Python 3.12 を {AppDir}\python にサイレント導入
# - システムPATHは変更しない（PrependPath=0 / Include_launcher=0）
# - 既に導入済みならスキップ（冪等）
# 終了コード: 0 = 成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [string]$TmpDir,
    [string]$Version = '3.12.10'
)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $AppDir 'install.log'
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
function Log { param([string]$Message) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

Log '--- setup_python start ---'
$pyDir = Join-Path $AppDir 'python'
$pyExe = Join-Path $pyDir 'python.exe'

if (Test-Path $pyExe) {
    Log "python already installed: $pyExe (skip)"
    exit 0
}

$installer = Join-Path $TmpDir "python-$Version-amd64.exe"
if (-not (Test-Path $installer)) {
    $url = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
    Log "downloading $url"
    & curl.exe -L --fail --retry 3 --connect-timeout 30 -o $installer $url
    if ($LASTEXITCODE -ne 0) { throw "python download failed (curl exit $LASTEXITCODE)" }
}

Log 'installing python (silent, to app dir)'
$installArgs = @(
    '/quiet',
    'InstallAllUsers=1',
    "TargetDir=$pyDir",
    'PrependPath=0',
    'Include_launcher=0',
    'Include_pip=1',
    'Include_test=0',
    'Include_doc=0',
    'Shortcuts=0',
    'AssociateFiles=0',
    'CompileAll=0'
)
$p = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    throw "python installer exit code $($p.ExitCode)"
}
if (-not (Test-Path $pyExe)) { throw 'python.exe not found after install' }

$ver = & $pyExe --version 2>&1
Log "installed: $ver"
Log '--- setup_python done ---'
exit 0

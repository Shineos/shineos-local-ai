# setup_python.ps1 - Python 3.12 を {AppDir}\python にサイレント導入
# - システムPATHは変更しない（PrependPath=0 / Include_launcher=0）
# - 既に導入済みならスキップ（冪等）
# - 失敗時は原因（MSIログ末尾・終了コード）を install.log に記録する
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

try {
    Log '--- setup_python start ---'
    $pyDir = Join-Path $AppDir 'python'
    $pyExe = Join-Path $pyDir 'python.exe'

    if (Test-Path $pyExe) {
        Log "python already installed: $pyExe (skip)"
        exit 0
    }

    $installer = Join-Path $TmpDir "python-$Version-amd64.exe"
    if (-not (Test-Path $installer)) {
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            throw 'curl.exe not found (Windows 10 1803 以降が必要)'
        }
        $url = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
        Log "downloading $url"
        & curl.exe -L --fail --retry 3 --connect-timeout 30 -o $installer $url
        if ($LASTEXITCODE -ne 0) { throw "python download failed (curl exit $LASTEXITCODE)" }
        $size = (Get-Item $installer).Length
        Log "downloaded: $([math]::Round($size / 1MB, 1)) MB"
        if ($size -lt 20MB) { throw "python download looks invalid (${size} bytes) - proxy/block page の可能性" }
    }
    else {
        Log "installer already exists: $installer (skip download)"
    }

    Log 'installing python (silent, to app dir)'
    $msiLog = Join-Path $AppDir 'logs\python-install.log'
    New-Item -ItemType Directory -Force -Path (Join-Path $AppDir 'logs') | Out-Null
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
        'CompileAll=0',
        "/log `"$msiLog`""
    )
    $p = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru
    Log "python installer exit code: $($p.ExitCode)"
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        if (Test-Path $msiLog) {
            Log '--- python MSI log (last 40 lines) ---'
            Get-Content $msiLog -Tail 40 | ForEach-Object { Log "MSI: $_" }
        }
        throw "python installer exit code $($p.ExitCode)"
    }
    if (-not (Test-Path $pyExe)) { throw "python.exe not found after install: $pyExe" }

    $ver = & $pyExe --version 2>&1
    Log "installed: $ver"
    Log '--- setup_python done ---'
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK: $($_.ScriptStackTrace)"
    exit 1
}

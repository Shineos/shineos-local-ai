# setup_python.ps1 - Python 3.12 を {AppDir}\python にサイレント導入
# - システムPATHは変更しない（PrependPath=0 / Include_launcher=0）
# - 利用可能な Python 3.11/3.12 が既にあれば再利用（冪等・最短化）
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

function Test-UsablePython {
    param([string]$Candidate)
    if (-not (Test-Path $Candidate)) { return $false }
    try {
        $v = & $Candidate -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")' 2>$null
        if ($v -match '^3\.(11|12)$') { return $true }
    }
    catch { }
    return $false
}

function Find-PythonExe {
    # レジストリ（インストール済みPythonのInstallPath）
    foreach ($rp in @(
        'HKLM:\SOFTWARE\Python\PythonCore\3.12\InstallPath',
        'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore\3.12\InstallPath',
        'HKCU:\SOFTWARE\Python\PythonCore\3.12\InstallPath'
    )) {
        $val = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
        if ($val) {
            $dir = $val.'(default)'
            if (-not $dir) { $dir = $val.ExecutablePath }
            if ($dir -and (Test-Path $dir)) {
                $c = Join-Path $dir 'python.exe'
                if (Test-UsablePython $c) { return $c }
            }
        }
    }
    # よくある導入先（過去の不完全導入を含む）
    foreach ($c in @(
        (Join-Path $env:ProgramFiles 'Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        'C:\Program\python.exe'
    )) {
        if (Test-UsablePython $c) { return $c }
    }
    return $null
}

try {
    Log '--- setup_python start ---'
    $pyDir = Join-Path $AppDir 'python'
    $pyExe = Join-Path $pyDir 'python.exe'
    $pathFile = Join-Path $AppDir 'python-path.txt'

    # --- 既存の利用可能なPythonを探す（あればインストールをスキップ） ---
    $found = $null
    if (Test-Path $pyExe) { $found = $pyExe }
    if (-not $found) { $found = Find-PythonExe }
    if ($found) {
        Log "using existing python: $found"
        $found | Out-File -FilePath $pathFile -Encoding ascii
        Log '--- setup_python done (reuse) ---'
        exit 0
    }

    # --- ダウンロード（未取得時のみ） ---
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

    # --- サイレントインストール ---
    Log 'installing python (silent, to app dir)'
    $msiLog = Join-Path $AppDir 'logs\python-install.log'
    New-Item -ItemType Directory -Force -Path (Join-Path $AppDir 'logs') | Out-Null
    $installArgs = @(
        '/quiet',
        'InstallAllUsers=1',
        ("TargetDir=`"$pyDir`""),   # スペースを含むため引用符が必須（WiX Burnの引数解析仕様）
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

    # --- 導入先の確認（過去の不完全導入が原因で別場所に入るケースを探索で救済） ---
    if (Test-Path $pyExe) { $found = $pyExe }
    else {
        Log "python.exe not found at expected path: $pyExe - searching..."
        $found = Find-PythonExe
    }
    if (-not $found) { throw "python.exe not found after install: $pyExe" }
    Log "using python: $found"
    $found | Out-File -FilePath $pathFile -Encoding ascii

    $ver = & $found --version 2>&1
    Log "installed: $ver"
    Log '--- setup_python done ---'
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK: $($_.ScriptStackTrace)"
    exit 1
}

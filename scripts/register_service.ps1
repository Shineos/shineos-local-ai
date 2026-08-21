# register_service.ps1 - NSSM で Windowsサービス「ShineosLocalAI」を登録・起動
# - システム環境変数は変更しない（NSSM の AppEnvironmentExtra に注入）
# - 再インストール時は既存サービスを削除し、data ディレクトリを初期化する
#   （WEBUI_AUTH=False は「ユーザー0の新規DB」でのみ有効なため）
# 終了コード: 0 = 成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [int]$Port = 8080,
    [string]$Model = 'qwen2.5:3b'
)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $AppDir 'install.log'
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
function Log { param([string]$Message) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
Log '--- register_service start ---'
$nssm = Join-Path $AppDir 'tools\nssm.exe'
if (-not (Test-Path $nssm)) { throw "nssm.exe not found: $nssm" }
$owui = Join-Path $AppDir 'venv\Scripts\open-webui.exe'
if (-not (Test-Path $owui)) { throw "open-webui.exe not found: $owui" }

$svc = 'ShineosLocalAI'
$dataDir = Join-Path $AppDir 'data'
$logDir = Join-Path $AppDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# --- 既存サービス・データのクリーンアップ（再インストール対応） ---
Log 'removing existing service (if any)'
& sc.exe stop $svc 2>$null | Out-Null
& sc.exe delete $svc 2>$null | Out-Null
Start-Sleep -Seconds 1

if (Test-Path $dataDir) {
    Log 'removing previous data directory (fresh install)'
    Remove-Item -Recurse -Force $dataDir
}

# --- サービス登録 ---
$secret = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
Log 'nssm install'
& $nssm install $svc $owui 'serve' "--port $Port" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'nssm install failed' }
& $nssm set $svc AppDirectory $AppDir | Out-Null
& $nssm set $svc Start SERVICE_AUTO_START | Out-Null
& $nssm set $svc AppStdout (Join-Path $logDir 'openwebui.log') | Out-Null
& $nssm set $svc AppStderr (Join-Path $logDir 'openwebui.err.log') | Out-Null
& $nssm set $svc AppRotateFiles 1 | Out-Null
& $nssm set $svc AppRotateBytes 10485760 | Out-Null

# 環境変数（値に空白を含むものは引用符で囲む。nssm 仕様）
$envs = @(
    ('"DATA_DIR=' + $dataDir + '"'),
    ('"WEBUI_SECRET_KEY=' + $secret + '"'),
    '"WEBUI_AUTH=False"',
    '"ENABLE_SIGNUP=False"',
    '"OLLAMA_BASE_URL=http://127.0.0.1:11434"',
    ('"DEFAULT_MODELS=' + $Model + '"'),
    '"RAG_EMBEDDING_ENGINE=ollama"',
    '"RAG_EMBEDDING_MODEL=nomic-embed-text"',
    '"ENABLE_WEB_SEARCH=True"',
    '"WEB_SEARCH_ENGINE=duckduckgo"'
)
Log 'nssm set AppEnvironmentExtra'
& $nssm set $svc AppEnvironmentExtra $envs | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'nssm AppEnvironmentExtra failed' }

# --- 起動 ---
Log 'starting service'
& $nssm start $svc | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'service start failed' }
Log '--- register_service done ---'
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK: $($_.ScriptStackTrace)"
    exit 1
}
exit 0

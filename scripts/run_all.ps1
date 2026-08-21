# run_all.ps1 - 長いセットアップ手順を1つのコンソールで順に実行するラッパー
# - 各ステップの開始・成功・失敗をコンソールと install.log の両方に記録する
# - いずれかのステップが失敗したら、そこで停止して終了コードを返す
# - 失敗時は実際のエラー内容（例外メッセージ・出力末尾）を step_error.txt に書き、
#   インストーラのエラーダイアログに表示する（install.logが作れない状況でも原因が分かる）
# 終了コード: 0 = 全ステップ成功 / 非0 = 失敗
param(
    [string]$AppDir,
    [string]$TmpDir,
    [string]$PythonVersion = '3.12.10',
    [string]$Model = 'qwen2.5:7b',
    [string]$OpenWebuiVersion = '0.11.0'
)

$ErrorActionPreference = 'Continue'
$LogFile = Join-Path $AppDir 'install.log'
$here = $PSScriptRoot
$ErrorFile = Join-Path $TmpDir 'step_error.txt'

function Save-Error {
    param([string]$Message)
    $Message | Out-File -FilePath $ErrorFile -Encoding ascii
}

# --- 事前チェック: アプリフォルダに書き込めるか（作成できない場合は即座に原因を報告） ---
try {
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $testFile = Join-Path $AppDir '.write_test'
    Set-Content -Path $testFile -Value 'ok' -ErrorAction Stop
    Remove-Item $testFile -ErrorAction SilentlyContinue
}
catch {
    $msg = "FATAL: cannot write to $AppDir - $($_.Exception.Message)"
    Save-Error $msg
    Write-Output $msg
    exit 90
}

function Log-Console {
    param([string]$Message)
    Write-Output $Message
    try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8 } catch { }
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Script,
        [string[]]$Params
    )
    Log-Console "===== STEP START: $Name ====="
    $outFile = Join-Path $TmpDir 'step_output.txt'
    # PS 5.1 は配列引数をネイティブコマンドに渡す際、空白を含むパスを
    # 「C:\Program」のように途中で切ってしまう（= 根本原因）。
    # cmd /c でコマンドライン文字列を組み立て、引用符を確実に保持する
    $childPath = Join-Path $here $Script
    $cmdLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $childPath + '"'
    foreach ($p in $Params) { $cmdLine += ' "' + $p + '"' }
    & cmd.exe /d /c $cmdLine 2>&1 | Tee-Object -FilePath $outFile
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Log-Console "===== STEP FAILED: $Name (exit $code) ====="
        $tail = Get-Content $outFile -Tail 15 -ErrorAction SilentlyContinue
        Save-Error ("STEP FAILED: $Name (exit $code)`n" + ($tail -join "`n"))
        Get-Content $outFile -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Log-Console "  | $_" }
        exit $code
    }
    Log-Console "===== STEP OK: $Name ====="
}

Invoke-Step -Name 'Python (3.12)' -Script 'setup_python.ps1' -Params @('-AppDir', $AppDir, '-TmpDir', $TmpDir, '-Version', $PythonVersion)
Invoke-Step -Name 'Ollama' -Script 'setup_ollama.ps1' -Params @('-AppDir', $AppDir, '-TmpDir', $TmpDir)
Invoke-Step -Name 'AI Models' -Script 'setup_openwebui.ps1' -Params @('-AppDir', $AppDir, '-Mode', 'models', '-Model', $Model)
Invoke-Step -Name 'Open WebUI' -Script 'setup_openwebui.ps1' -Params @('-AppDir', $AppDir, '-Mode', 'app', '-OpenWebuiVersion', $OpenWebuiVersion)

Log-Console '===== ALL STEPS COMPLETED ====='
exit 0

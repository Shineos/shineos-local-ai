# configure_model.ps1 - Open WebUI のモデル設定を最適化する
# - サインイン（admin@localhost / admin）して API 経由で「Shineos Chat」モデル設定を作成・上書き
# - 別名カスタムモデル（id=Shineos Chat, base_model_id=実モデル）として作成する。
#   同名（id=base_model_id）で作成した設定は Open WebUI 0.10.x でモデル一覧に
#   マージされず、ツールが無効化されないため（2026-08-22 実機検証）。
# - meta.builtinTools を全て無効化し、モデルにツール（write_note 等）を提供しない。
#   ツールがあるとモデルが関数呼び出しを選び、チャットにテキスト回答が残らず
#   「応答なし」になるため（実機検証済み）。
# - params.think=false で qwen3系の思考モードを無効化（応答なし防止）
# - 全モデルに num_ctx 4096 を設定（長文・RAG 対応）
# 冪等: 同一モデル id の設定は上書きされる
# 終了コード: 0 = 成功 / 非0 = 失敗
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$Model = 'qwen2.5:3b',
    [string]$Email = 'admin@localhost',
    [string]$Password = 'admin',
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($LogFile) { New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null }
function Log { param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    if ($LogFile) { $line | Out-File -FilePath $LogFile -Append -Encoding utf8 }
    Write-Host $line
}

try {
    # ---------- 1. WebUI の起動を待つ（最大5分） ----------
    $health = "$BaseUrl/health"
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $r = Invoke-RestMethod -Uri $health -TimeoutSec 5
            if ($r.status) { $ready = $true; break }
        } catch { Start-Sleep -Seconds 10 }
        Start-Sleep -Seconds 10
    }
    if (-not $ready) { throw "Open WebUI が応答しません: $health" }
    Log "Open WebUI ready: $BaseUrl"

    # ---------- 2. サインインして JWT を取得 ----------
    $signinBody = @{ email = $Email; password = $Password } | ConvertTo-Json
    $session = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/auths/signin" -Body $signinBody -ContentType 'application/json' -TimeoutSec 30
    if (-not $session.token) { throw 'signin に成功しましたが token を取得できませんでした' }
    $headers = @{ Authorization = "Bearer $($session.token)" }
    Log "signed in as $Email"

    # ---------- 3. 「Shineos Chat」モデル設定を作成（同一 id は上書き） ----------
    # ツールを全て無効化（モデルが関数呼び出しを選んで「応答なし」になるのを防ぐ）
    $appModel = 'Shineos Chat'
    $builtinTools = @{
        notes            = $false
        time             = $false
        knowledge        = $false
        chats            = $false
        memory           = $false
        web_search       = $true
        image_generation = $false
        code_interpreter = $false
        channels         = $false
        tasks            = $false
        automations      = $false
        calendar         = $false
    }
    $params = @{
        think   = $false
        num_ctx = 4096
        # 応答の安定性向上（言語追従がぶれないように温度を下げる）
        temperature = 0.5
        # native でツール（Web検索）をモデルに提供する。
        # web_search ツールのみ有効化し、他のツールは無効（「回答なし」防止）。
        # ファイル生成ツール（PDF/PPT）は別途ツールサーバーとして登録する。
        function_calling = 'native'
        # ユーザーの言語に合わせて回答言語を切り替える。
        # 質問の言語を判断できない場合のみデフォルトの日本語で回答する
        system  = 'あなたは多言語対応のAIアシスタントです。ユーザーの質問が日本語の場合は日本語で、英語の場合は英語で、中国語の場合は中国語で回答してください。質問の言語を判断できない場合は、デフォルトの日本語で回答してください。'
    }
    $body = @{
        id             = $appModel
        base_model_id  = $Model
        name           = $appModel
        meta           = @{
            capabilities  = @{ tools = $true }
            builtinTools = $builtinTools
        }
        params         = $params
        access_grants  = @()
        is_active      = $true
    } | ConvertTo-Json -Depth 6

    # PS 5.1 の Invoke-RestMethod は文字列 Body を ISO-8859-1 で送信し日本語が
    # 化ける（既知のバグ）ため、UTF-8 バイト配列に変換して送る
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    # 0.10.x は同名 id の再作成がエラーになるため、update を試してから create にフォールバック
    $updated = $null
    try {
        $updated = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/models/model/update" -Headers $headers -Body $jsonBytes -ContentType 'application/json' -TimeoutSec 60
    } catch {
        $updated = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/models/create" -Headers $headers -Body $jsonBytes -ContentType 'application/json' -TimeoutSec 60
    }
    # ---------- 4. UI言語を日本語に設定（フロントの初回表示に反映） ----------
    try {
        $langBody = @{ ui = @{ locale = 'ja-JP'; language = 'ja-JP' } } | ConvertTo-Json -Depth 4
        $langBytes = [System.Text.Encoding]::UTF8.GetBytes($langBody)
        Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/users/user/settings/update" -Headers $headers -Body $langBytes -ContentType 'application/json' -TimeoutSec 30 | Out-Null
        Log 'ui language set to ja-JP'
    } catch { Log 'WARNING: ui language setting failed' }
    Log "model configured: $appModel (base=$Model, think=$($params.think), num_ctx=$($params.num_ctx), tools=disabled)"
    Log 'configure_model done'
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) { Log "DETAIL: $($_.ErrorDetails.Message)" }
    Log "STACK: $($_.ScriptStackTrace)"
    exit 1
}

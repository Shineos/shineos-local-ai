; ============================================================================
; Shineos Local AI - インストーラ（Inno Setup 6.7.3）
;
; 無料ツールとして公開する「ダブルクリック一発・初期設定なし」の
; ローカルLLM + RAG + チャット環境インストーラ
;
; ビルド: ISCC.exe installer.iss  → dist\ShineosLocalAI-Setup-<ver>.exe
; 詳細: ../../docs/shineos-local-ai-build.md
; ============================================================================

#define MyAppName "Shineos Local AI"
#define MyAppVersion "1.0.19"
#define MyAppPublisher "Shineos Inc."
#define MyAppURL "https://shineos.com"
#define MyAppExeName "open-webui.exe"
#define MyAppId "{{3E3DBB6F-6C7B-4E47-9FDB-C7CBE7DA9246}"

; --- 更新時に変更する定数 ----------------------------------------------------
#define PythonVersion "3.12.10"        ; python.org のアーカイブURLに依存
#define OpenWebuiVersion "0.11.0"      ; pip install open-webui==<version>
#define Port "8080"                    ; open-webui serve --port <Port>

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL=https://shineos.com/contact/
DefaultDirName={autopf}\ShineosLocalAI
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\assets\app.ico
UninstallDisplayIcon={app}\assets\app.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputDir=..\dist
OutputBaseFilename=ShineosLocalAI-Setup-{#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName}

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

; --- セットアップ中のみ使用するファイル（{tmp} に展開） ----------------------
; 長い処理（Python/Ollama/モデルDL/venv）はファイルコピー前に実行するため、
; dontcopy で展開し [Code] から ExtractTemporaryFile する
[Files]
Source: "..\scripts\preflight.ps1";        DestDir: "{tmp}"; Flags: dontcopy
Source: "..\scripts\setup_python.ps1";     DestDir: "{tmp}"; Flags: dontcopy
Source: "..\scripts\setup_ollama.ps1";     DestDir: "{tmp}"; Flags: dontcopy
Source: "..\scripts\setup_openwebui.ps1";  DestDir: "{tmp}"; Flags: dontcopy
Source: "..\scripts\register_service.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "..\scripts\wait_ready.ps1";       DestDir: "{tmp}"; Flags: dontcopy
Source: "..\vendor\nssm.exe";              DestDir: "{tmp}"; Flags: dontcopy

; --- インストール先へ配置するファイル ----------------------------------------
Source: "..\vendor\nssm.exe";              DestDir: "{app}\tools"; Flags: ignoreversion
Source: "..\scripts\start_openwebui.bat";  DestDir: "{app}";       Flags: ignoreversion
Source: "..\assets\app.ico";               DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\vendor\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}";     Flags: ignoreversion

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "http://localhost:{#Port}"; IconFilename: "{app}\assets\app.ico"

; --- アンインストール時の完全削除 --------------------------------------------
[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\venv"
Type: filesandordirs; Name: "{app}\python"
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\tools"
Type: files; Name: "{app}\install.log"
Type: files; Name: "{userdesktop}\ShineosLocalAI-はじめに.txt"

[Code]
var
  ProgressPage: TOutputProgressWizardPage;
  ModelPage: TInputOptionWizardPage;
  RamGB: Integer;
  PortFree: Boolean;
  OsOk: Boolean;
  SelectedModel: String;

const
  PREFLIGHT_INI = 'preflight.ini';

{ ---------- 共通ヘルパー ---------- }

procedure ExtractSetupFiles;
begin
  ExtractTemporaryFile('preflight.ps1');
  ExtractTemporaryFile('setup_python.ps1');
  ExtractTemporaryFile('setup_ollama.ps1');
  ExtractTemporaryFile('setup_openwebui.ps1');
  ExtractTemporaryFile('register_service.ps1');
  ExtractTemporaryFile('wait_ready.ps1');
  ExtractTemporaryFile('nssm.exe');
end;

{ preflight.ps1 を実行し、結果（OS・ポート8080・RAM）を読み取る }
procedure RunPreflight;
var
  RC: Integer;
  Ini: String;
begin
  PortFree := True;
  OsOk := True;
  RamGB := 8;
  Ini := ExpandConstant('{tmp}\' + PREFLIGHT_INI);
  if Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\preflight.ps1') + '" -IniPath "' + Ini + '"',
      '', SW_HIDE, ewWaitUntilTerminated, RC) then
  begin
    OsOk := (GetIniString('preflight', 'os_ok', 'no', Ini) = 'yes');
    PortFree := (GetIniString('preflight', 'port_8080_free', 'no', Ini) = 'yes');
    RamGB := GetIniInt('preflight', 'ram_gb', 8, 4, 512, Ini);
  end;
end;

{ 一時フォルダのPowerShellスクリプトを実行（非表示・待機） }
function RunPowerShell(Script, Params: String; var ResultCode: Integer): Boolean;
begin
  Result := Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\' + Script) + '" ' + Params,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;


{ ---------- ウィザード初期化 ---------- }

procedure InitializeWizard;
begin
  ExtractSetupFiles;
  RunPreflight;

  if not OsOk then
    MsgBox('Windows 10 / 11（64bit）以外の環境では Shineos Local AI を利用できません。' + #13#10 +
           'インストールを中止してください。', mbError, MB_OK);

  if not PortFree then
    MsgBox('ポート 8080 が他のプログラムで使用されています。' + #13#10 +
           '該当プログラムを終了してからインストールをやり直してください。', mbError, MB_OK);

  ModelPage := CreateInputOptionPage(wpSelectDir,
    'AIモデルの選択',
    'インストールするAIモデルを選択してください',
    '検出メモリ: ' + IntToStr(RamGB) + ' GB。動作が重い場合は「軽量」を選択してください。',
    True, False);
  ModelPage.Add('qwen3.5:4b（推奨）　性能重視・16GB以上で快適・約3.4GB');
  ModelPage.Add('qwen3.5:2b（軽量）　8GB機に最適・約2.7GB');
  ModelPage.SelectedValueIndex := 0;
end;

{ ---------- 長い処理（キャンセル可能な進捗ページ） ---------- }

function RunLongSteps(AppDir: String): Boolean;
var
  RC: Integer;
begin
  Result := False;
  ProgressPage := CreateOutputProgressPage('インストール中',
    'Shineos Local AI のセットアップを実行しています。' + #13#10 +
    '完了まで約30〜90分かかります（Ollama本体1.5GB＋AIモデル3.4GBなど合計約6GBのダウンロードを含みます）。' + #13#10 +
    'インストール中はウィンドウを閉じないでください。');
  try
    ProgressPage.Show;

    ProgressPage.SetText('環境チェック中...', '');
    RunPreflight;
    if not OsOk then
    begin
      MsgBox('Windows 10 / 11（64bit）以外の環境ではインストールできません。', mbError, MB_OK);
      Exit;
    end;
    if not PortFree then
    begin
      MsgBox('ポート 8080 が使用中のため続行できません。' + #13#10 +
             '該当プログラムを終了してから「次へ」をもう一度押してください。', mbError, MB_OK);
      Exit;
    end;

    ProgressPage.SetProgress(5, 100);
    ProgressPage.SetText('インストール中...', 'ログは表示されているログウィンドウにリアルタイム表示されます（各ステップの開始・成功・失敗を明記）');
    if not RunPowerShellVisible('run_all.ps1',
        '-AppDir "' + AppDir + '" -TmpDir "' + ExpandConstant('{tmp}') + '" -Model "' + SelectedModel + '" -PythonVersion "{#PythonVersion}" -OpenWebuiVersion "{#OpenWebuiVersion}"', RC)
       or (RC <> 0) then
    begin
      MsgBox('インストールに失敗しました。' + #13#10 +
             'ログ: ' + AppDir + '\install.log' + #13#10 +
             '「次へ」をもう一度押すと続きから再開できます。', mbError, MB_OK);
      Exit;
    end;

    ProgressPage.SetProgress(100, 100);
    Result := True;
  finally
    ProgressPage.Hide;
    ProgressPage.Free;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  AppDir: String;
begin
  Result := True;
  if CurPageID = wpReady then
  begin
    AppDir := ExpandConstant('{app}');
    if ModelPage.SelectedValueIndex = 1 then
      SelectedModel := 'qwen3.5:2b'
    else
      SelectedModel := 'qwen3.5:4b';
    Result := RunLongSteps(AppDir);
  end;
end;

{ ---------- 仕上げ（ファイルコピー後） ---------- }

procedure WriteUsageFile(AppDir: String);
var
  S: String;
begin
  S := 'Shineos Local AI - はじめに' + #13#10 +
       '=====================================' + #13#10 + #13#10 +
       'ブラウザで http://localhost:{#Port} を開くと、そのままチャットを始められます（ログイン不要・初期設定なし）。' + #13#10 + #13#10 +
       '・使用モデル: ' + SelectedModel + '（文書検索用: nomic-embed-text）' + #13#10 +
       '・RAG（文書の質問）: チャット画面の「+」→ ファイルアップロード → その内容について質問' + #13#10 +
       '・Web検索: チャット入力欄のWeb検索ボタンをONにすると利用できます（DuckDuckGo・APIキー不要）' + #13#10 +
       '・完全オフライン: Web検索ボタンをOFFのままにすれば、一切インターネットに接続しません' + #13#10 + #13#10 +
       '・PCを再起動しても自動で起動します（Windowsサービス: ShineosLocalAI）' + #13#10 +
       '・アンインストール: 設定アプリ → アプリ → Shineos Local AI' + #13#10 +
       '・再インストールするとデータ（アップロードした文書など）は初期化されます' + #13#10 + #13#10 +
       '不具合やご相談は https://shineos.com/contact/ まで。' + #13#10;
  SaveStringToFile(ExpandConstant('{userdesktop}\ShineosLocalAI-はじめに.txt'), S, True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  RC: Integer;
  AppDir: String;
  Ready: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    AppDir := ExpandConstant('{app}');
    Ready := False;
    ProgressPage := CreateOutputProgressPage('仕上げ',
      'サービスを登録して起動しています...');
    try
      ProgressPage.Show;

      ProgressPage.SetText('Windowsサービスを登録中...', '');
      Ready := RunPowerShell('register_service.ps1', '-AppDir "' + AppDir + '" -Model "' + SelectedModel + '"', RC) and (RC = 0);
      if not Ready then
      begin
        MsgBox('サービスの登録に失敗しました。' + #13#10 +
               'ログ: ' + AppDir + '\install.log' + #13#10 + #13#10 +
               '手動で起動する場合は ' + AppDir + '\start_openwebui.bat をダブルクリックしてください。',
               mbError, MB_OK);
      end
      else
      begin
        ProgressPage.SetText('Open WebUI を起動しています（初回は数分かかります）...', '');
        Ready := RunPowerShell('wait_ready.ps1', '-Port {#Port} -TimeoutSec 180', RC) and (RC = 0);
        if not Ready then
          MsgBox('Open WebUI の起動確認がタイムアウトしました。' + #13#10 +
                 'ブラウザで http://localhost:{#Port} を開いて起動を確認してください。' + #13#10 +
                 'ログ: ' + AppDir + '\logs\openwebui.err.log', mbInformation, MB_OK);
      end;

      WriteUsageFile(AppDir);
      WizardForm.FinishedLabel.Caption :=
        'インストールが完了しました。' + #13#10 + #13#10 +
        'デスクトップの「Shineos Local AI」をダブルクリックするか、' + #13#10 +
        'ブラウザで http://localhost:{#Port} を開いてください。ログインは不要です。' + #13#10 + #13#10 +
        '詳しい使い方はデスクトップの「ShineosLocalAI-はじめに.txt」を参照してください。';
    finally
      ProgressPage.Hide;
      ProgressPage.Free;
    end;
  end;
end;

{ ---------- アンインストール ---------- }

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RC: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    { サービス停止 → 削除（ファイル削除前に実行される） }
    Exec(ExpandConstant('{sys}\sc.exe'), 'stop ShineosLocalAI', '', SW_HIDE, ewWaitUntilTerminated, RC);
    Exec(ExpandConstant('{sys}\sc.exe'), 'delete ShineosLocalAI', '', SW_HIDE, ewWaitUntilTerminated, RC);
    { Ollama のサービス不在時に登録したフォールバックサービスの削除 }
    Exec(ExpandConstant('{sys}\sc.exe'), 'stop ShineosOllama', '', SW_HIDE, ewWaitUntilTerminated, RC);
    Exec(ExpandConstant('{sys}\sc.exe'), 'delete ShineosOllama', '', SW_HIDE, ewWaitUntilTerminated, RC);
  end;
end;

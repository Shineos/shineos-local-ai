# Shineos Local AI — 無料インストーラツール 構築ドキュメント

> 作成: 2026-08-20 | Shineos Inc.
> ステータス: 実装完了（Windows実機検証は未実施 — §8 参照）
> 関連: [Zenn記事（ベースとなる技術構成）](https://zenn.dev/shineos/articles/local-llm-rag-web-search-with-ollama)

---

## 1. 目的・方針

Shineos Inc. が Zenn で公開した「Ollama + Open WebUI」によるローカルRAG環境を、**技術者でない一般のWindowsユーザーでもダブルクリック一発で導入できる無料ツール**として公開する。

本ツールは**無料**で公開する。公開に際しては「無料であること」と問い合わせ先（https://shineos.com/contact/）を明示する。

### 製品の約束（ユーザーへの約束事）

| 約束 | 実現方法 |
|------|----------|
| ダブルクリックでインストール完了 | Inno Setup 製インストーラ（管理者権限自動要求） |
| 初期設定なし・インストール後すぐ利用 | `WEBUI_AUTH=False` でログイン不要（新規DB限定の公式機能。初回起動前にNSSM環境変数で設定） |
| PC再起動後も自動起動 | NSSM で Windowsサービス登録（自動起動ON） |
| 完全オフラインで利用可能 | チャット・RAG（文書アップロードQA）はインストール完了後、一切インターネット不要。Open WebUI は既定で外部通信ゼロ |
| 外部検索も利用可能（オプション） | 内蔵 DuckDuckGo 検索（APIキー不要）を初回起動時から利用可能に。SearXNG への切替も設定可能（§3.2） |

### スコープ外（v1ではやらない）

- SearXNG 本体の同梱（WindowsではDocker必須のため。設定案内のみ §3.2）
- 自社RAGエンジンの実装（Open WebUI 内蔵RAGで代替）
- コード署名（SmartScreen警告は案内で対応 §10）
- GitHub CI、自動ビルド

---

## 2. 製品概要

### 2.1 インストール処理フロー

```
[ShineosLocalAI-Setup-1.0.0.exe（ダブルクリック）]
    │
    ├─ ① 環境チェック（Windows 10/11 64bit・ポート8080空き・RAM検出）
    ├─ ② AIモデル選択ページ（既定: qwen3.5:4b / 軽量: qwen3.5:2b）
    ├─ ③ Python 3.12 を {app}\python にサイレント導入（PATH汚染なし）
    ├─ ④ Ollama を公式インストーラでサイレント導入（サービス不在時はNSSMフォールバック）
    ├─ ⑤ AIモデルダウンロード（qwen3.5:4b=3.4GB + nomic-embed-text=274MB）
    ├─ ⑥ venv 作成 → torch(CPU) → open-webui をインストール
    ├─ ⑦ NSSM でサービス「ShineosLocalAI」登録（環境変数注入・自動起動ON）
    ├─ ⑧ サービス起動 → /health ポーリング（最大180秒）
    └─ ⑨ 完了画面＋デスクトップに「はじめに.txt」とショートカット
            │
            ▼
    [ブラウザで http://localhost:8080 → ログイン不要でチャット開始]
```

- ③〜⑥は**キャンセル可能な進捗ページ**（進捗バー＋ステップ表示）で実行。完了まで約20〜50分（モデルダウンロードが大半）
- 全ステップの詳細ログは `{app}\install.log` に記録
- 各ステップは冪等（再実行時はスキップ/上書き）

### 2.2 利用モード

| モード | 動作 | 既定 |
|--------|------|------|
| 完全オフライン | チャット＋RAG（文書アップロードQA）。外部通信ゼロ | **既定動作** |
| Web検索（DuckDuckGo） | チャット入力欄のWeb検索ボタンONで利用。APIキー不要 | 機能は有効化済み・ボタンは既定OFF |
| SearXNG 切替 | サービス環境変数で切替（§3.2） | 切替手順のみ提供 |

### 2.3 環境変数（サービス注入分）

サービス「ShineosLocalAI」には NSSM の `AppEnvironmentExtra` で以下を注入する（**システム環境変数は一切変更しない** → setx不使用・アンインストールが完全）：

| 変数 | 値 | 理由 |
|------|-----|------|
| `DATA_DIR` | `{app}\data` | 未設定だとデータがパッケージ内に入るため必須 |
| `WEBUI_SECRET_KEY` | ランダム64文字（インストール毎に生成） | 認証セッション固定化・再現性 |
| `WEBUI_AUTH` | `False` | ログイン不要（新規DB限定。再インストール時はdataを初期化） |
| `ENABLE_SIGNUP` | `False` | アカウント登録画面を出さない |
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` | ローカルOllamaを明示 |
| `RAG_EMBEDDING_ENGINE` | `ollama` | 埋め込みをOllamaに切替（torch実行回避） |
| `RAG_EMBEDDING_MODEL` | `nomic-embed-text` | ローカル埋め込みモデル |
| `ENABLE_WEB_SEARCH` | `True` | DuckDuckGo検索を利用可能に |
| `WEB_SEARCH_ENGINE` | `duckduckgo` | APIキー不要のプロバイダ |

---

## 3. モデル選定

### 3.1 選定結果

| | **既定: qwen3.5:4b** | 軽量オプション: qwen3.5:2b |
|---|---|---|
| サイズ | 3.4GB | 2.7GB |
| 8GB機 | 動作可能（メモリ余裕少・やや遅い） | 快適 |
| 16GB以上 | 快適 | — |
| ライセンス | Apache 2.0（商用可・無償・同梱可） | 同左 |
| 特徴 | 256K文脈・画像対応マルチモーダル・201言語 | 軽量 |

選定根拠:
1. **業務利用のライセンス**: qwen3.5系は Apache 2.0（Ollamaレジストリ・HuggingFaceで確認）。商用利用・再配布・同梱が無償で可能
2. **8GB機での動作**: qwen3.5:4b は3.4GB。メモリ試算（モデル3.4GB＋文脈約1GB＋Open WebUI約1GB＋Windows約3GB ≈ 8.5〜9GB）で8GB機ではスワップ気味になるが動作する。16GB以上で快適
3. **日本語・性能**: 新世代モデルで小規模でも日本語QAの実用下限を満たす。業務利用は「文書検索→引用付き回答」の抽出型RAG QAを主用途と想定
4. ユーザーが「8GB機で動く」ことを確認した上で既定に決定（2026-08-20）

### 3.2 検索エンジンの切替（SearXNG）

DuckDuckGo はレート制限（1時間あたりのリクエスト上限）があり、大量利用には不向き。SearXNG に切替える場合（自己運用のSearXNGインスタンスが必要。WindowsではDocker必須のため同梱しない）:

1. `{app}` をエクスプローラで開く
2. 管理者PowerShellで:
   ```
   cd "C:\Program Files\ShineosLocalAI"
   .\tools\nssm.exe set ShineosLocalAI AppEnvironmentExtra "DATA_DIR=C:\Program Files\ShineosLocalAI\data" "WEBUI_AUTH=False" "OLLAMA_BASE_URL=http://127.0.0.1:11434" "RAG_EMBEDDING_ENGINE=ollama" "RAG_EMBEDDING_MODEL=nomic-embed-text" "ENABLE_WEB_SEARCH=True" "WEB_SEARCH_ENGINE=searxng" "SEARXNG_QUERY_URL=http://127.0.0.1:8888/search?q=<query>"
   ```
3. `.\tools\nssm.exe restart ShineosLocalAI`

---

## 4. 技術前提（検証済みの事実・2026-08-20時点）

公式ドキュメント・ソースコードで確認済み。**元の提案文書から修正した点を含む**:

| 項目 | 事実 | 元文書からの修正 |
|------|------|------------------|
| Open WebUI v0.11.0 | pip導入は Python 3.11/3.12 のみ（3.13不可） | — |
| torch | 実質ハード依存（Windows既定pipでCUDA版2.5GB超）。**CPU版を先に導入すれば回避**（`pip install torch --index-url https://download.pytorch.org/whl/cpu`） | サイズ対策を追加 |
| WEBUI_AUTH | 現行でも有効。**新規DB（ユーザー0）限定**。フロントエンドがsignin APIを呼ぶ既知の不具合あり（未解決・要因はCookie残存） | 「初期設定後に変更不可」→「新規DB限定」に修正 |
| ポート | `open-webui serve` は `PORT` 環境変数が効かず **`--port 8080` フラグ必須** | **3000→8080に修正**（3000はDockerマッピング） |
| DATA_DIR | 未設定だと**パッケージ内**にデータが入る（Windowsでは必須設定） | 必須設定として追加 |
| ヘルスチェック | `GET /health`（認証不要）→ 起動確認に使用 | — |
| RAG | 内蔵RAG＋`RAG_EMBEDDING_ENGINE=ollama`でOllama埋め込みに切替可 → torch実行回避・自前RAGエンジン不要 | 自社RAGエンジン実装を廃止 |
| Web検索 | `ENABLE_WEB_SEARCH` / `WEB_SEARCH_ENGINE` 環境変数が存在（ソース確認）。DuckDuckGoはAPIキー不要 | 「DuckDuckGo API」表記を修正（公式APIは存在しない） |
| qwen3.5 | `qwen3.5:4b`=3.4GB / `qwen3.5:2b`=2.7GB がOllamaライブラリに存在。**Apache 2.0** | モデルをqwen2.5:3b→qwen3.5系に変更 |
| Ollama | `OllamaSetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` 有効（winget実績）。公式DL URL 有効。MIT | — |
| NSSM | 2.24・パブリックドメイン。`AppEnvironmentExtra KEY=VALUE` でサービスに環境変数注入可 | setx方式を廃止（環境変数汚染ゼロ） |

---

## 5. ファイル構成

```
shineos-local-ai/                      # 本リポジトリ（Shineos/shineos-local-ai）
├── README.md                          # 概要・方針・利用モード・ライセンス
├── LICENSE                            # MIT（株式会社シャイオス）
├── docs/
│   ├── build.md                       ← 本ドキュメント
│   └── user-guide.md                  # ユーザー向けマニュアル（配布物に同梱）
├── installer/
│   └── installer.iss                  # Inno Setup 6.7.3 スクリプト（本体）
├── scripts/
│   ├── preflight.ps1                  # OS/ポート/RAMチェック → preflight.ini
│   ├── setup_python.ps1               # Python 3.12 → {app}\python
│   ├── setup_ollama.ps1               # Ollama導入＋サービス確認/フォールバック
│   ├── setup_openwebui.ps1            # -Mode models: モデルDL / -Mode app: venv+torch+open-webui
│   ├── register_service.ps1           # NSSM登録（環境変数込み）・自動起動・開始
│   ├── wait_ready.ps1                 # /health ポーリング
│   └── start_openwebui.bat            # 手動起動用（デバッグ・サービス停止時の代替）
├── assets/
│   └── app.ico                        # インストーラ/ショートカット用アイコン
└── vendor/
    ├── nssm.exe                       # NSSM 2.24 win64（公式nssm.cc・パブリックドメイン）
    ├── THIRD-PARTY-NOTICES.txt        # 同梱・導入コンポーネントのライセンス一覧
    └── README.md                      # ベンダーバイナリの出典・更新手順
```

### インストール後の配置（`{app}` = `C:\Program Files\ShineosLocalAI`）

```
{app}\
├── python\                      # Python 3.12（自己完結・PATH汚染なし）
├── venv\                        # open-webui 実行環境（torch CPU）
├── data\                        # Open WebUI データ（DB・アップロード文書）
├── logs\                        # openwebui.log / ollama.log / install.log
├── tools\nssm.exe               # サービス管理用（移動・削除しないこと）
├── start_openwebui.bat          # 手動起動用
└── assets\app.ico
```

---

## 6. ビルド手順（Windows）

### 6.1 前提

- Windows 10/11（64bit）の開発機
- [Inno Setup 6.7.3](https://jrsoftware.org/isinfo.php) 導入済み
  （`winget install --id=JRSoftware.InnoSetup -e` でも可）
- ⚠️ **Inno Setup 7系は不使用**: 7系は API が変更され（`Add` が1引数化など）、かつ
  ISCC が「Non-commercial use only」と表示するため商用利用にライセンスが必要になる
  可能性がある。6系（6.7.3）は商用利用が無償で、本スクリプトは6系APIで書かれている

### 6.2 コンパイル

```
# コマンドライン（Inno Setup 付属の ISCC.exe）
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\installer.iss
```

または GUI の Inno Setup で `installer\installer.iss` を開いて「Compile」。

出力: `shineos-local-ai\dist\ShineosLocalAI-Setup-1.0.0.exe`

### 6.3 ビルド前チェックリスト

- [ ] `installer.iss` の `#define AppVersion` / `OutputBaseFilename` が新しいバージョンになっている
- [ ] 必要に応じて `#define OpenWebuiVersion` を最新安定版に更新（§7.2）
- [ ] `vendor\nssm.exe` が存在する（更新手順は vendor/README.md）
- [ ] Windows 10/11（64bit）のクリーン環境でテスト（§8）

---

## 7. 更新・保守

### 7.1 バージョン更新（ユーザー向け）

バージョンはインストーラの `AppVersion` と `OutputBaseFilename` で管理。配布時は GitHub Releases 等に
### 7.1 バージョン更新（リリース手順）

1. `installer.iss` の `#define MyAppVersion`（および `OutputBaseFilename`）を更新
2. main に push し、`git tag v<新バージョン> && git push origin v<新バージョン>`
3. GitHub Actions が自動ビルドし、GitHub Releases に `ShineosLocalAI-Setup-<version>.exe` を公開する（§10.1）
4. README のバージョンバッジ（shields.io）は自動更新される。ユーザーガイドのバージョン表記は必要に応じて更新

### 7.2 open-webui バージョンの更新

`installer.iss` の `#define OpenWebuiVersion` を更新する（`setup_openwebui.ps1` は .iss から `-OpenWebuiVersion` 引数で受け取るため、.iss の更新で反映される。スクリプト内の既定値も念のため同期）。

```
pip index versions open-webui   # 最新安定版の確認（要Windows/Python）
```

更新時は以下を必ず確認する:
- WEBUI_AUTH の動作が変わっていないか（新規DB限定の制約が続いているか）
- 必要Pythonバージョン（3.11/3.12）が変わっていないか

### 7.3 Python バージョンの更新

`installer.iss` の `#define PythonVersion` を更新する（`setup_python.ps1` は `-Version` 引数で受け取る。スクリプト内の既定値も念のため同期）。python.org のアーカイブURL:
`https://www.python.org/ftp/python/<version>/python-<version>-amd64.exe`

### 7.4 モデルの追加・変更

- モデル選択ページの選択肢は `installer.iss` の [Code]（`ModelPage.Add`）と `setup_openwebui.ps1` の `-Model` 引数で管理
- 追加時はメモリ試算（§3.1）とモデルライセンスを確認すること

---

## 8. テストチェックリスト（Windows実機）

> ⚠️ 本ドキュメント作成時点（2026-08-20）は macOS 上での実装・静的検証のみ実施済み。
> **以下は Windows 実機での検証必須項目**。リリース前に全て通過させること。

### テスト環境

| 項目 | 仕様 |
|------|------|
| OS | Windows 11 Pro（22H2以降）× 2台以上（8GB RAM機・16GB RAM機） |
| ストレージ | 空き容量15GB以上（モデル3.4GB＋venv約2GB＋Python等） |
| ネットワーク | インストール時のみ（初回モデルDL約3.7GB） |

### 検証項目

**T1. インストール正常系（8GB機・16GB機 各1台以上）**
- [ ] exeダブルクリック → UACの管理者権限要求が出る
- [ ] モデル選択ページでRAMが正しく表示される（検出値±2GB）
- [ ] 既定（qwen3.5:4b）でインストールがエラーなく完了（20〜50分）
- [ ] 完了画面が表示され、デスクトップに「Shineos Local AI」ショートカットと「ShineosLocalAI-はじめに.txt」が作成される
- [ ] ショートカットでブラウザが開き、**ログイン画面なしで**チャット画面が表示される
- [ ] モデル「qwen3.5:4b」が選択でき、日本語の応答が返る

**T2. RAG機能**
- [ ] チャットの「+」→ PDFアップロード → 内容に関する日本語の質問 → 文書に基づく回答と引用が返る
- [ ] アップロード中もチャットが動作する（埋め込みがOllama経由で動いている）

**T3. 自動起動（再起動テスト）**
- [ ] PC再起動後、サービス「ShineosLocalAI」が自動起動し、http://localhost:8080 にアクセスできる
- [ ] ※ Ollama が起動していない場合の症状確認（サービス「Ollama」または「ShineosOllama」の状態を確認。手動起動 `sc start Ollama` で復旧することを確認）

**T4. Web検索（DuckDuckGo）**
- [ ] チャットのWeb検索ボタンON → 最新ニュースの質問 → 検索結果を反映した回答が返る（レート制限時は空回答になる既知の制約を確認）

**T5. 完全オフライン動作**
- [ ] ネットワーク切断状態でPC起動 → チャット・RAGが正常動作（Web検索ボタンOFFのまま）

**T6. アンインストール**
- [ ] 設定 → アプリ → Shineos Local AI → アンインストール
- [ ] サービス「ShineosLocalAI」が停止・削除されている（`sc query ShineosLocalAI` がエラー）
- [ ] `C:\Program Files\ShineosLocalAI` が完全に削除されている
- [ ] システム環境変数に残留物がない（setx不使用のため）
- [ ] デスクトップのショートカット・はじめに.txt が削除されている
- [ ] ※ ユーザーの `.ollama` モデルは残す仕様（削除しない）

**T7. 再インストール・失敗復旧**
- [ ] インストール後に再実行 → 冪等に完了し、data が初期化されログイン不要のまま動く
- [ ] モデルDL中にネットワーク切断 → エラー表示と install.log の記録 → 再実行で復旧

### 検証成功基準（元提案書の基準を踏襲）

1. インストール成功率100%（10台の異なるWindows環境）
2. 初回起動時、アカウント登録なしでチャット画面が表示される
3. RAG: PDFアップロード→質問→回答生成が正常動作
4. PC再起動後、サービスが自動起動し利用可能
5. アンインストールでサービス・ファイルが完全削除

---

## 9. 既知の制約・リスク

| リスク | 内容 | 対策 |
|--------|------|------|
| SmartScreen警告 | 未署名exeは「保護されませんでした」表示が出る | README・配布ページに「詳細情報→実行」の案内を明記。実績ができたらコード署名を検討 |
| 8GB機の性能 | qwen3.5:4b は動作するがメモリ余裕が少なく応答が遅い | モデル選択ページ・ユーザーガイドで2b（軽量）への切替を案内。再インストールで変更可 |
| WEBUI_AUTHの既知不具合 | ブラウザのCookie残存時にsignin APIが400になるケース（未解決） | 新規DB（毎回data初期化）＋シークレットウィンドウの案内をユーザーガイドに記載 |
| Ollamaの自動起動 | 公式サービスの再起動時挙動は環境依存。フォールバック（ShineosOllama）を用意 | T3の再起動テストで確認。問題時は `sc start Ollama` |
| DuckDuckGoのレート制限 | 大量検索で空回答（Open WebUIの既知issue） | ユーザーガイドに記載。SearXNG切替手順（§3.2）を提供 |
| インストール時間 | 20〜50分（モデルDL3.7GBが大半） | 進捗ページに時間表示。ダウンロード失敗時は再実行で復旧（冪等） |
| 再インストールでデータ初期化 | {app}\data を削除するためアップロード文書は消える | ユーザーガイド・はじめに.txtに明記 |
| アンインストール後にOllama本体が残る | モデル（.ollama）はユーザーデータとして残す仕様 | ユーザーガイドに明記（完全削除は `ollama` コマンド等で手動） |

---

## 10. 公開・配布

### 10.1 配布フロー（GitHub Actions 自動リリース）

exe のビルドは **GitHub Actions が自動実行**する（`.github/workflows/release.yml`）:

1. バージョンタグを push（例: `git tag v1.0.0 && git push origin v1.0.0`）
2. ワークフローが Windows ランナーで Inno Setup 6.7.3 を導入 → `ISCC.exe installer\installer.iss` でビルド
3. 成功すると **GitHub Releases に `ShineosLocalAI-Setup-<version>.exe` が自動添付**される

手動ビルド（workflow_dispatch）でビルドのみ行いアーティファクト確認も可能。

配布ページ（Releases）に以下を明記する:
- 無料であること・商用サポートの問い合わせ先（https://shineos.com/contact/）
- SmartScreenの回避手順（詳細情報→実行）
- 動作要件（Windows 10/11 64bit・8GB RAM以上・空き15GB・インストール時にネット接続）

---

## 11. ライセンス

| コンポーネント | ライセンス | 備考 |
|---------------|-----------|------|
| 本プロジェクトのコード（.iss/.ps1/.bat等） | MIT | — |
| Ollama | MIT | インストーラが自動導入 |
| Open WebUI | BSD-3-Clause | pipで導入 |
| qwen3.5（4b/2b） | Apache 2.0 | 商用・再配布可 |
| nomic-embed-text | Apache 2.0 | 同上 |
| NSSM | パブリックドメイン | vendor/nssm.exe として同梱 |

詳細は `shineos-local-ai/vendor/THIRD-PARTY-NOTICES.txt` を参照。

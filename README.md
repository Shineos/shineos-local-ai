# Shineos Local AI

**ダブルクリック一発・初期設定なしで使える、Windows向けローカルAI（チャット + RAG + Web検索）無料インストーラ**

[Shineos Inc.](https://shineos.com) が公開する無料ツールです。Ollama + Open WebUI によるローカルAI環境を、技術者でない方でもインストールした瞬間から使えるようにパッケージ化しました。

## できること

| 機能 | 内容 |
|------|------|
| ローカルチャット | インストール後すぐ利用。ログイン・アカウント登録は不要 |
| RAG（文書質問） | PDF等の文書をアップロードして、その内容を日本語で質問・引用付き回答 |
| Web検索（オプション） | チャットのWeb検索ボタンONで最新情報を参照（DuckDuckGo・APIキー不要） |
| 完全オフライン運用 | Web検索をOFFのままなら、一切インターネットに接続しない（機密資料の利用に最適） |
| 自動起動 | PC再起動後も Windowsサービスとして自動起動 |

## 動作環境

- Windows 10 / 11（64bit）
- メモリ 8GB 以上（16GB 以上推奨）
- 空き容量 15GB 以上
- インストール時のみインターネット接続（Ollama本体1.5GB＋AIモデル約3.4GBなど、**合計約6GB**のダウンロードのため。所要約30〜90分）

## ダウンロード

[![Latest Release](https://img.shields.io/github/v/release/Shineos/shineos-local-ai?sort=semver&label=Latest%20Release)](https://github.com/Shineos/shineos-local-ai/releases/latest)

[Releases](https://github.com/Shineos/shineos-local-ai/releases) ページから最新の `ShineosLocalAI-Setup-<version>.exe` をダウンロードし、**ダブルクリックするだけでインストール**できます。

※ コード署名済み（SignPath）のため、通常は発行元が表示されそのまま実行できます。まれに「発行元の確認」が出る場合は「実行」を選択してください。

## 使い方

1. `ShineosLocalAI-Setup-<version>.exe` をダブルクリック（管理者権限を要求されます）
2. AIモデルを選択（既定: qwen3.5:4b / 軽量: qwen3.5:2b）
3. インストール完了後、ブラウザで **http://localhost:8080** を開くだけ

詳細は [docs/user-guide.md](docs/user-guide.md) を参照してください。

## 利用モード

- **完全オフライン（既定）**: チャット・RAGはすべて端末内で完結。外部送信ゼロ
- **Web検索**: チャット入力欄のWeb検索ボタンONでDuckDuckGo検索を利用可能（レート制限あり）。SearXNGへの切替手順は[構築ドキュメント](docs/build.md#32-検索エンジンの切替searxng)参照

## 構成

```
shineos-local-ai/
├── installer/installer.iss   # Inno Setup 6.7.3 インストーラスクリプト
├── scripts/                  # セットアップ用 PowerShell / バッチ
├── assets/app.ico            # アイコン
├── vendor/                   # nssm.exe・サードパーティライセンス
└── docs/user-guide.md        # ユーザーマニュアル
```

## ビルド

Windows機で [Inno Setup 6.7.3](https://jrsoftware.org/isinfo.php) を導入し:

```
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\installer.iss
```

出力: `dist\ShineosLocalAI-Setup-<version>.exe`

※ 通常は GitHub Actions が自動ビルドして GitHub Releases に公開します（`v*` タグの push で発火）。

ビルド・テスト・更新手順の詳細は [構築ドキュメント](docs/build.md) を参照してください。

## ライセンス

本プロジェクトのコードは MIT License です。同梱・導入するコンポーネントのライセンスは [vendor/THIRD-PARTY-NOTICES.txt](vendor/THIRD-PARTY-NOTICES.txt) を参照してください。

## 問い合わせ

- 不具合・導入支援・カスタマイズのご相談: https://shineos.com/contact/
- 本ツールは **無料** です。製造業向けオフラインAI（図面・マニュアル検索）のご相談もお気軽にどうぞ

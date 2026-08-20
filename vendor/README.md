# vendor — 同梱バイナリとサードパーティライセンス

## nssm.exe（同梱）

| 項目 | 内容 |
|------|------|
| バージョン | 2.24（win64） |
| 出典 | https://nssm.cc/download （`https://nssm.cc/release/nssm-2.24.zip` 内の `nssm-2.24/win64/nssm.exe`） |
| ライセンス | パブリックドメイン（nssm 公式: "nssm is public domain. You may unconditionally use it for any purpose."） |
| SHA-256 | `f689ee9af94b00e9e3f0bb072b34caaf207f32dcb4f5782fc9ca351df9a06c97` |

### 更新手順

```
curl -L -o nssm-2.24.zip https://nssm.cc/release/nssm-2.24.zip
unzip nssm-2.24.zip
cp nssm-2.24/win64/nssm.exe ../vendor/nssm.exe
shasum -a 256 ../vendor/nssm.exe   # SHA-256 を上表に更新
```

**注意**: サービス登録後は nssm.exe を移動・削除しないこと（サービスはこの実行ファイルを参照している）。アンインストール時にサービスを削除してからファイルが削除される設計です。

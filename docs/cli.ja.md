# CLI リファレンス

[English](cli.md) | **日本語**

ワークスペースのルートで実行します。

```sh
dart run kareki
```

## オプション

| オプション | 説明 |
|---|---|
| `--root <path>` | ワークスペースのルート。デフォルトはカレントディレクトリ。 |
| `-f`, `--format <name>` | 出力フォーマット: `text` \| `json`。`kareki-config.yaml` の設定を上書きします。 |
| `--packages <name>` | 解析対象を指定したパッケージに限定。複数指定可。 |
| `--rule <id>` | 指定したルールのみ有効化。複数指定可。 |
| `--strict` | `unused_pub_dependency` において、`dev_dependencies` を `dependencies` と同じように扱う。 |
| `--baseline <path>` | baseline ファイルのパス。baseline に記録された検出は出力から除外されます。`kareki-config.yaml` の `baseline:` を上書きします。 |
| `--write-baseline` | 現在の検出結果を baseline ファイルに書き出して終了。`--baseline <path>` または config の `baseline:` 指定が必要です。 |
| `-h`, `--help` | 使い方を表示。 |

## 終了コード

| コード | 意味 |
|---|---|
| `0` | 検出なし。 |
| `1` | 1 件以上の検出を報告。 |
| `64` | CLI の使い方が不正。 |

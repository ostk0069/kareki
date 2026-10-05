---
title: CLIリファレンス
weight: 2
---

ワークスペースのルートで実行します。

```sh
dart run kareki
```

## Options

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

## Exit codes

| コード | 意味 |
|---|---|
| `0` | 検出なし。 |
| `1` | 1 件以上の検出を報告。 |
| `2` | 名前・型の解決が完了しなかった。検出結果の出力やベースライン更新は行わない。 |
| `64` | CLI の使い方が不正。 |

## 宣言IDによる解析

`pub get` / ワークスペースのbootstrapとコード生成を済ませてから実行します。

```sh
dart run kareki --rule unused_element,test_only_used,unused_parameter_optional
```

今回移行したルールは `unused_element`、`test_only_used`、`unused_parameter_optional` です。
引数本体の未使用判定など他のルールは従来のアルゴリズムを使用します。
resolved方式では `--packages` と `ignore.packages` は報告対象を限定し、
参照元は検出済みワークスペース全体から集めます。
パッケージ検出段階の `packages.exclude` は引き続き対象外です。
生成・除外ファイルも参照元になるため、解析可能である必要があります。

解析エラーは標準エラー出力へ表示し、終了コード2を返します。
保守的な近似を使用した場合も標準エラー出力へ通知します。
既存のtext/JSON検出結果とベースラインの形式は維持しますが、
同名宣言によって隠れていた未使用コードが新たに検出されることがあります。
差分を確認してからベースラインへ受け入れてください。

`dart run kareki doctor` で、同じ解析方式による
抑制・ベースライン検証ができます。旧方式と解析方式の切替設定は撤去しました。
doctorは解決失敗や、保守的な近似により安全に検証できない場合に終了コード2を返します。
旧バージョンのbaselineは検出差分を確認してから整理してください。
詳細は[doctor](doctor.ja.md)を参照してください。

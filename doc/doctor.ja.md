---
title: Doctor
weight: 5
---

`kareki doctor` は、対象ファイルがない除外設定、存在しないパッケージ、効果のない抑制コメント、不要になったベースライン項目などを検出します。問題を報告するだけで、ファイルは変更しません。

```sh
dart run kareki doctor
```

## 検査項目

| 種別 | 意味 |
|---|---|
| `unused-exclude` | `exclude.files` の項目に一致する `.dart` ファイルがワークスペース内にない。 |
| `unused-exclude-parameter-name` | `exclude.parameter_names` の項目が、現在の `unused_parameter`・`unused_parameter_optional` の指摘を抑制していない。 |
| `unused-ignore-package` | `ignore.packages` の項目に一致するワークスペース内のパッケージがない。 |
| `unused-ignore-dependencies-package` | `ignore.dependencies` のキーに一致するワークスペース内のパッケージがない。 |
| `unused-ignore-dependency` | 抑制対象の依存パッケージが、そのパッケージの `pubspec.yaml` に宣言されていない。 |
| `unused-ignore-directive` | ファイル単位・行単位の抑制コメントが指摘を抑制していない。行単位の場合は対象行を `<path>:<line>` で報告する。 |
| `unused-baseline-entry` | ベースライン項目が現在の指摘に一致しない。コードの削除・移動のほか、使用されるようになった場合も含む。 |

ユーザーが追加した項目だけを検査します。`**/*.g.dart` の除外など、組み込みのデフォルト設定は指摘しません。

## 終了コード

| コード | 意味 |
|---|---|
| `0` | すべての検査が完了し、問題がない。 |
| `1` | すべての検査が完了し、1 件以上の問題がある。 |
| `2` | 解析に失敗した、または解析警告により安全に検査を完了できない。`1` より優先する。 |
| `64` | CLI オプションまたは kareki の設定が不正。 |

## 検査を完了できない場合

引数名の除外、抑制コメント、ベースライン項目の検査には、解決済みの参照を使います。これらの検査では、1 回の解析結果を共有します。

参照の解決や gen-l10n 入力の読み込みに失敗した場合は、結果を報告せず `2` で終了します。解析警告があり、使用状況が確定しない場合は、使用状況に依存する検査を行わず、理由を標準エラー出力に示して `2` で終了します。対象ファイルがない除外設定など、参照の解析を必要としない検査の結果は報告できます。

終了コード `2` で JSON の一覧が空でも、**問題なしという意味ではありません**。その結果だけを根拠に、抑制設定やベースライン項目を削除しないでください。具体例と確認の進め方は[解析の仕組み](how-it-works.ja.md#結果を確認するとき)を参照してください。

ライブラリから利用する場合は、`DoctorRunner().analyze(request)` または `run(request)` を `await` します。[API の実行例と注意点（英語）](https://github.com/ostk0069/kareki/blob/main/example/example.md#programmatic-api)も参照してください。

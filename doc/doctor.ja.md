# Doctor

[English](doctor.md) | **日本語**

`kareki doctor` は、`kareki-config.yaml` の内容が現在のワークスペースの実態と整合しているかを検証します。何にもマッチしなくなった glob、すでに存在しないパッケージや依存を指している `ignore.*` のエントリ、もう何も抑制していない `// kareki: ignore_for_file=...` / `// kareki: ignore=...` ディレクティブなど、現実から取り残された設定を浮き上がらせます。

```sh
dart run kareki doctor
```

| Issue 種別 | 意味 |
|---|---|
| `unused-exclude` | `exclude.files` のエントリがワークスペース内のどの `.dart` ファイルにもマッチしなかった。 |
| `unused-ignore-package` | `ignore.packages` の名前がワークスペースのパッケージに存在しない。 |
| `unused-ignore-dependencies-package` | `ignore.dependencies` のキーがワークスペースのパッケージに存在しない。 |
| `unused-ignore-dependency` | `ignore.dependencies.<pkg>` の下に列挙されている値が、そのパッケージの `pubspec.yaml` に宣言されていない。 |
| `unused-ignore-directive` | `// kareki: ignore_for_file=<rule>` または `// kareki: ignore=<rule>` ディレクティブが、実際の検出を何も抑制していない。行単位ディレクティブの場合、対象行は `<path>:<line>` として報告されます。 |
| `unused-baseline-entry` | baseline ファイル内のエントリが、現在の検出のいずれにもマッチしない。抑制対象のデッドコードがすでに削除・移動されています。 |

検証されるのは **ユーザーが追加した** エントリのみです。ビルトインのデフォルト（例: 同梱の `**/*.g.dart` 除外）は決して指摘されません。

設定がクリーンであれば `0` で終了し、1 件以上の Issue があれば `1` で終了します。

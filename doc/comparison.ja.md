---
title: 類似ツールとの比較
weight: 8
---

kareki は、ワークスペース全体の未使用コード検出と、CI での継続的な整理に重点を置いています。

## 機能比較

✅ 対応（オプションでの有効化を含む）、△ 一部のみ対応、— 該当機能なし。

| 機能 | **kareki** | [ciach][ciach-repo] | [Dart Code Linter][dcl-repo] | [dependency_validator][dependency-repo] | [Dart 標準解析][dart-unused] |
|---|:---:|:---:|:---:|:---:|:---:|
| [未使用の public 宣言・メンバーの検出](#unused-public-declarations) | ✅ | ✅ | ✅ | — | — |
| 未使用の private 宣言・メンバーの検出 | — | ✅ | ✅ | — | ✅ |
| [public enum の未使用値の検出](#unused-enum-values) | ✅ | ✅ | ✅ | — | — |
| [起点から到達できない public 宣言の循環参照の検出](#unreachable-cycles) | ✅ | — | — | — | — |
| [未使用 Dart ファイルの検出](#unused-dart-files) | ✅ | — | ✅ | — | — |
| [未使用の pub 依存パッケージの検出](#unused-pub-dependencies) | ✅ | — | — | ✅ | — |
| [呼び出し元から渡されない public API の省略可能な引数の検出](#unsupplied-optional-parameters) | ✅ | — | — | — | — |
| [テストからしか使われない public 宣言の検出](#test-only-declarations) | ✅ | — | — | — | — |
| l10n 専用の未使用検査 | 近日対応 | — | ✅ | — | — |
| [ベースラインによる新規指摘だけの報告](#baseline) | ✅ | — | — | — | — |
| [不要な除外設定・ベースライン項目の検査](#stale-configuration) | ✅ | — | — | — | — |
| 未使用 public 宣言の自動削除 | 近日対応 | △ | — | — | — |

- ✅ でも解析対象には制限があり、たとえば kareki は演算子を検査しません。
- enum の値は宣言・メンバーの行とは分けて比較しています。
- Dart Code Linter のメンバー検査は public / private ともオプションで有効にします。enum の値も対象です。[CLI][dcl-cli]
- Dart Code Linter の l10n 検査は Dart クラスのメンバーが対象です。クラス名の既定パターンは `I18n$` で、`AppLocalizations` には `--class-pattern AppLocalizations` を指定します。[設定][dcl-l10n]
- ciach の自動削除には、報告のみで削除しない指摘があります。[README][ciach-readme]
- 引数の行は「呼び出し元が値を渡すか」の検査です。Dart Code Linter の[本体で読まれない引数の検査][dcl-parameters]や、Dart の[private 宣言向けの検査][dart-parameter]とは対象が異なります。

## 各機能の説明

### 未使用の public 宣言・メンバー {#unused-public-declarations}

解析範囲内で利用が確認できない公開クラス、関数、フィールド、メソッドなどを検出します。kareki は、解析の起点から到達できない対象宣言を `unused_element` で報告します。[解析の具体例](how-it-works.ja.md#解析の流れ)を参照してください。

### public enum の未使用値 {#unused-enum-values}

enum 型自体が使われていても、各値が使われているかを個別に検査します。例えば `Status.active` しか使わない場合、`Status.archived` は未使用の可能性があります。kareki は `unused_element` で判定し、`Status.values` に到達する場合は全値を保持します。[各ルールの判定根拠](how-it-works.ja.md#各ルールが使う根拠)を参照してください。

### 起点から到達できない public 宣言の循環参照 {#unreachable-cycles}

互いに参照し合っていても、`main` などの起点から到達できない公開宣言のまとまりを検出します。kareki では、循環内に参照があるだけでは使用中とはみなしません。[解析方式の違い](#解析方式の違い)を参照してください。

### 未使用 Dart ファイル {#unused-dart-files}

別の対象ファイルから import / export / part されておらず、解析の起点でもない Dart ファイルを検出します。kareki の `unused_file` は、ファイル内の宣言への到達可能性とは別に、ファイルへの参照を検査します。[各ルールの判定根拠](how-it-works.ja.md#各ルールが使う根拠)を参照してください。

### 未使用の pub 依存パッケージ {#unused-pub-dependencies}

`pubspec.yaml` に宣言されていても、利用が確認できない依存パッケージを検出します。kareki の `unused_pub_dependency` は Dart の import だけでなく、対応するアノテーション、ビルド設定、ネイティブプラグイン、アセットからの利用も考慮します。[import 以外の利用](configuration.ja.md#import-以外で使われる依存パッケージ)を参照してください。

### 呼び出し元から渡されない public API の省略可能な引数 {#unsupplied-optional-parameters}

対象の呼び出し元が一度も値を指定しない、省略可能な名前付き引数・位置引数を検出します。関数本体で既定値を読んでいても、利用されていない API オプションを見つけられます。kareki の `unused_parameter_optional` は、不明な呼び出し経路が残る引数を報告しません。[省略可能な引数の使用状況](how-it-works.ja.md#省略可能な引数の使用状況)を参照してください。

### テストからしか使われない public 宣言 {#test-only-declarations}

テストの起点からは到達できても、本番コードの起点からは到達できない公開宣言を検出します。kareki の `test_only_used` は、利用がまったく確認できないコードと、テストだけで使うコードを区別します。[各ルールの判定根拠](how-it-works.ja.md#各ルールが使う根拠)を参照してください。

### ベースラインによる新規指摘だけの報告 {#baseline}

既存の指摘を保存し、次回以降は一致する指摘を報告から除外します。段階的に整理しながら、CI で新しく増えた問題を検出できます。kareki は `--baseline` で読み込み、`--write-baseline` で保存します。[ベースラインの使い方](baseline.ja.md)を参照してください。

### 不要な除外設定・ベースライン項目の検査 {#stale-configuration}

対象ファイルや未使用宣言の削除などにより、適用先がなくなった除外設定、抑制コメント、ベースライン項目を検出します。`kareki doctor` はファイルを変更せずに報告しますが、解析が不確かな場合は使用状況に依存する検査を完了できないことがあります。[doctor の検査項目](doctor.ja.md#検査項目)を参照してください。

## 解析方式の違い

kareki は解析の起点から参照をたどるため、相互参照だけが残る public 宣言も検出対象です。ただし、生成コードや設定、動的呼び出しの扱いによって保持される場合があります。ciach の `--transitive` は未使用コードからしか参照されない宣言を検出しますが、循環参照は対象外です。Dart Code Linter は参照の有無で判定します。[ciach の説明][ciach-transitive]、[Dart Code Linter の判定処理][dcl-analyzer]

同名宣言の区別やパッケージ横断の参照収集は、ciach も対応しています。これらは kareki だけの利点ではありません。[ciach の実装][ciach-finder]、[モノレポ対応][ciach-readme]

## 使い分けの補足

kareki は private 宣言・メンバーの未使用検出を Dart 標準解析に任せ、public API やパッケージ横断の検査を補います。型検査や lint も含め、`dart analyze` / `flutter analyze` は併用します。[Dart の未使用宣言の診断][dart-unused]

dependency_validator は未使用依存だけでなく、宣言漏れや `dependencies` / `dev_dependencies` の配置間違いも検出します。[dependency_validator の説明][dependency-readme]

速度・誤検出率は比較実測していません。✅ は削除の安全性を保証するものではなく、公開 API や動的呼び出しなどは、指摘の確認と削除後のテストが必要です。

## 比較した版

確認日：2026 年 10 月 10 日。公式ドキュメントとソースに基づく比較です。

| ツール | 比較した版 |
|---|---|
| kareki | [latest][kareki-source] |
| [ciach][ciach-repo] | [0.6.0][ciach-readme] |
| [Dart Code Linter][dcl-repo] | [4.4.2][dcl-readme] |
| [dependency_validator][dependency-repo] | [5.1.0][dependency-readme] |
| [Dart 標準解析][dart-unused] | [3.13.3][dart-unused] |

[kareki-source]: https://github.com/ostk0069/kareki/tree/main
[ciach-readme]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md
[ciach-transitive]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md#transitively-dead-code
[ciach-finder]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/lib/src/finder.dart
[dart-unused]: https://dart.dev/tools/diagnostics/unused_element
[dart-parameter]: https://dart.dev/tools/diagnostics/unused_element_parameter
[dcl-readme]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md
[dcl-cli]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md#cli
[dcl-analyzer]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/unused_code_analyzer/unused_code_analyzer.dart
[dcl-parameters]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/lint_analyzer/rules/rules_list/avoid_unused_parameters/visitor.dart
[dcl-l10n]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/cli/commands/check_unused_l10n_command.dart
[dependency-readme]: https://github.com/Workiva/dependency_validator/blob/7728cb7f27de46d3fefc515018f54b9aee3a2587/README.md

[ciach-repo]: https://github.com/leancodepl/ciach
[dcl-repo]: https://github.com/bancolombia/dart-code-linter
[dependency-repo]: https://github.com/Workiva/dependency_validator

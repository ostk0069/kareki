---
title: 類似ツールとの比較
weight: 8
---

kareki は、ワークスペース全体の未使用コード検出と、CI での継続的な整理に重点を置いています。

## 機能比較

✅ 対応（オプションでの有効化を含む）、△ 一部のみ対応、— 該当機能なし。

| 機能 | **kareki** | [ciach][ciach-options] | [Dart Code Linter][dcl-cli] | [dependency_validator][dependency-readme] | [Dart 標準解析][dart-unused] |
|---|:---:|:---:|:---:|:---:|:---:|
| [未使用の public 宣言・メンバーの検出](how-it-works.ja.md#解析の流れ) | ✅ | ✅ | ✅ | — | — |
| 未使用の private 宣言・メンバーの検出 | — | ✅ | ✅ | — | ✅ |
| public enum の未使用値の検出 | ✅ | ✅ | ✅ | — | — |
| [起点から到達できない public 宣言の循環参照の検出](#解析方式の違い) | ✅ | — | — | — | — |
| [未使用 Dart ファイルの検出](how-it-works.ja.md#各ルールが使う根拠) | ✅ | — | ✅ | — | — |
| [未使用の pub 依存パッケージの検出](configuration.ja.md#import-以外で使われる依存パッケージ) | ✅ | — | — | ✅ | — |
| [呼び出し元から渡されない public API の省略可能な引数の検出](how-it-works.ja.md#省略可能な引数の使用状況) | ✅ | — | — | — | — |
| [テストからしか使われない public 宣言の検出](how-it-works.ja.md#各ルールが使う根拠) | ✅ | — | — | — | — |
| l10n 専用の未使用検査 | 近日対応 | — | ✅ | — | — |
| [ベースラインによる新規指摘だけの報告](baseline.ja.md) | ✅ | — | — | — | — |
| [不要な除外設定・ベースライン項目の検査](doctor.ja.md#検査項目) | ✅ | — | — | — | — |
| 未使用 public 宣言の自動削除 | 近日対応 | △ | — | — | — |

- ✅ でも解析対象には制限があり、たとえば kareki は演算子を検査しません。
- enum の値は宣言・メンバーの行とは分けて比較しています。
- Dart Code Linter のメンバー検査は public / private ともオプションで有効にします。enum の値も対象です。[CLI][dcl-cli]
- Dart Code Linter の l10n 検査は Dart クラスのメンバーが対象です。クラス名の既定パターンは `I18n$` で、`AppLocalizations` には `--class-pattern AppLocalizations` を指定します。[設定][dcl-l10n]
- ciach の自動削除には、報告のみで削除しない指摘があります。[README][ciach-readme]
- 引数の行は「呼び出し元が値を渡すか」の検査です。Dart Code Linter の[本体で読まれない引数の検査][dcl-parameters]や、Dart の[private 宣言向けの検査][dart-parameter]とは対象が異なります。

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
| ciach | [0.6.0][ciach-readme] |
| Dart Code Linter | [4.4.2][dcl-readme] |
| dependency_validator | [5.1.0][dependency-readme] |
| Dart 標準解析 | [3.13.3][dart-unused] |

[kareki-source]: https://github.com/ostk0069/kareki/tree/main
[ciach-readme]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md
[ciach-transitive]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/README.md#transitively-dead-code
[ciach-finder]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/lib/src/finder.dart
[ciach-options]: https://github.com/leancodepl/ciach/blob/26682cb1874fc488d47875576ae4373957b9e591/lib/src/cli/args.dart
[dart-unused]: https://dart.dev/tools/diagnostics/unused_element
[dart-parameter]: https://dart.dev/tools/diagnostics/unused_element_parameter
[dcl-readme]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md
[dcl-cli]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/README.md#cli
[dcl-analyzer]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/unused_code_analyzer/unused_code_analyzer.dart
[dcl-parameters]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/analyzers/lint_analyzer/rules/rules_list/avoid_unused_parameters/visitor.dart
[dcl-l10n]: https://github.com/bancolombia/dart-code-linter/blob/adab62a10144a196cb05bab5d063e4128507f595/lib/src/cli/commands/check_unused_l10n_command.dart
[dependency-readme]: https://github.com/Workiva/dependency_validator/blob/7728cb7f27de46d3fefc515018f54b9aee3a2587/README.md

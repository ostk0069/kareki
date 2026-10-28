---
title: kareki ドキュメント
weight: 1
cascade:
  type: docs
---

`kareki` は、Dart / Flutter のワークスペース全体からデッドコードを見つけるツールです。Melos / pub workspace 内の参照をパッケージ横断で解析し、パッケージ単位の解析では見つけられない未使用の public API、ファイル、依存パッケージ、引数を検出します。

段階的に導入できるよう、生成コード向けのプリセット、既存の指摘を保存するベースライン、不要になった設定を確認する `kareki doctor` を備えています。

## クイックスタート

開発用依存に `kareki` を追加します。

```yaml {filename="pubspec.yaml"}
dev_dependencies:
  kareki: ^0.10.1
```

プロジェクトの依存パッケージを取得し、コード生成を実行してから、
ワークスペースのルートで実行します。

```sh
dart run kareki
```

## 検出できるもの

| ルール | 検出対象 |
|---|---|
| `unused_element` | ワークスペースのどこからも呼ばれていない public 宣言 |
| `unused_file` | import、export、part の対象になっていない Dart ファイル |
| `unused_pub_dependency` | 宣言されているものの、ソース、解析設定、ネイティブプラグイン、フォントアセットのいずれでも使用が確認できないパッケージ |
| `test_only_used` | テストからしか参照されていないライブラリ宣言 |
| `unused_parameter` | 宣言内で一度も読まれない引数 |
| `unused_parameter_optional` | どの呼び出し元からも渡されない省略可能な引数 |

## 類似ツールとの比較

| 機能 | **kareki** | [ciach](https://github.com/leancodepl/ciach) | [Dart Code Linter](https://github.com/bancolombia/dart-code-linter) | [dependency_validator](https://github.com/Workiva/dependency_validator) | [Dart 標準解析](https://dart.dev/tools/diagnostics/unused_element) |
|---|:---:|:---:|:---:|:---:|:---:|
| [未使用の public 宣言・メンバーの検出](comparison.ja.md#未使用の-public-宣言メンバー) | ✅ | ✅ | ✅ | — | — |
| [未使用の private 宣言・メンバーの検出](comparison.ja.md#未使用の-private-宣言メンバー) | ✅ | ✅ | ✅ | — | ✅ |
| [public enum の未使用値の検出](comparison.ja.md#public-enum-の未使用値) | ✅ | ✅ | ✅ | — | — |
| [起点から到達できない public 宣言の循環参照の検出](comparison.ja.md#起点から到達できない-public-宣言の循環参照) | ✅ | — | — | — | — |
| [未使用 Dart ファイルの検出](comparison.ja.md#未使用-dart-ファイル) | ✅ | — | ✅ | — | — |
| [未使用の pub 依存パッケージの検出](comparison.ja.md#未使用の-pub-依存パッケージ) | ✅ | — | — | ✅ | — |
| [呼び出し元から渡されない public API の省略可能な引数の検出](comparison.ja.md#呼び出し元から渡されない-public-api-の省略可能な引数) | ✅ | — | — | — | — |
| [テストからしか使われない public 宣言の検出](comparison.ja.md#テストからしか使われない-public-宣言) | ✅ | — | — | — | — |
| [l10n 専用の未使用検査](comparison.ja.md#未使用の翻訳キー) | ✅ | — | ✅ | — | — |
| [ベースラインによる新規指摘だけの報告](comparison.ja.md#ベースラインによる新規指摘だけの報告) | ✅ | — | — | — | — |
| [不要な除外設定・ベースライン項目の検査](comparison.ja.md#不要な除外設定ベースライン項目の検査) | ✅ | — | — | — | — |
| 未使用 public 宣言の自動削除 | 対応予定なし | ✅ | — | — | — |

各ツールの設定条件・制限、比較した版は[詳しい説明](comparison.ja.md)を参照してください。

## ドキュメント

- [CLI リファレンス](cli/) — コマンド、オプション、出力形式、終了コード
- [設定](configuration/) — ワークスペース設定、プリセット、除外、抑制
- [ベースライン](baseline/) — 既存コードベースへ段階的に導入する方法
- [Doctor](doctor/) — 不要になった除外設定や抑制を検出する方法
- [解析の仕組み](how-it-works/) — 解析の流れと制約
- [類似ツールとの比較](comparison/) — ciach、Dart Code Linter などの Dart 向けツールとの違い
- [運用のベストプラクティス](operations/) — cron と AI エージェントによる定期的なクリーンアップ

## リンク

- [GitHub](https://github.com/ostk0069/kareki) — ソースコードと Issue
- [pub.dev](https://pub.dev/packages/kareki) — パッケージのリリース
- [Changelog](https://github.com/ostk0069/kareki/blob/main/CHANGELOG.md) — 変更履歴

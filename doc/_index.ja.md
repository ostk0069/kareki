---
title: kareki ドキュメント
weight: 1
cascade:
  type: docs
---

`kareki` は、Dart / Flutter のワークスペース全体からデッドコードを見つけるツールです。Melos / pub workspace 内の参照をパッケージ横断で解析し、パッケージ単位の解析では見つけられない未使用の public API、ファイル、依存パッケージ、引数を検出します。

実際のコードベースで段階的に導入できるよう、生成コード向けのプリセット、既存の検出を保存するベースライン、設定の劣化を確認する `kareki doctor` を備えています。

## クイックスタート

開発用依存に `kareki` を追加します。

```yaml {filename="pubspec.yaml"}
dev_dependencies:
  kareki: ^0.7.0
```

ワークスペースのルートで実行します。

```sh
dart run kareki
```

## 検出できるもの

| ルール | 検出対象 |
|---|---|
| `unused_element` | ワークスペースのどこからも呼ばれていない public 宣言 |
| `unused_file` | import、export、part の対象になっていないDartファイル |
| `unused_pub_dependency` | 宣言されているもののソースコードから使われていないパッケージ |
| `test_only_used` | テストからしか参照されていないライブラリ宣言 |
| `unused_parameter` | 宣言内で一度も読まれない引数 |
| `unused_parameter_optional` | どの呼び出し元からも渡されない省略可能な引数 |

## ドキュメント

- [CLIリファレンス](cli/) — コマンド、オプション、出力形式、終了コード
- [設定](configuration/) — ワークスペース設定、プリセット、除外、抑制
- [ベースライン](baseline/) — 既存コードベースへ段階的に導入する方法
- [Doctor](doctor/) — 不要になった除外設定や抑制を検出する方法
- [解析の仕組み](how-it-works/) — 解析パイプラインと制約
- [運用のベストプラクティス](operations/) — cronとAIエージェントによる定期的なクリーンアップ

## リンク

- [GitHub](https://github.com/ostk0069/kareki) — ソースコードとIssue
- [pub.dev](https://pub.dev/packages/kareki) — パッケージのリリース
- [Changelog](https://github.com/ostk0069/kareki/blob/main/CHANGELOG.md) — 変更履歴

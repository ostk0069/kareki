# kareki

[English](README.md) | **日本語**

<img width="1645" height="496" alt="header image" src="https://github.com/user-attachments/assets/dc3b1903-8ff1-4556-9d4e-ac847e3c8bd0" />

[![pub package](https://img.shields.io/pub/v/kareki.svg)](https://pub.dev/packages/kareki)
[![CI](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml/badge.svg)](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

> 枯木 (kareki): 剪定が必要な、生命を失った枝。

`kareki` は、**Dart / Flutter のワークスペース全体からデッドコードを見つけるツール**です。

`dart analyze` が検出する未使用宣言は、基本的に単一パッケージ内の private なものに限られます。`kareki` は Melos / pub workspace 内のパッケージを横断して参照関係を解析し、使われていない public API、どこからも import されていないファイル、`pubspec.yaml` に残ったままの不要な依存パッケージなどを検出します。

## Why kareki?

|  | 特徴 |
|---|---|
| 🌲 | **ワークスペースを横断して解析** — Melos / pub workspace 内のすべてのパッケージについて、相互の参照関係を解析 |
| 🔓 | **public API も検出** — `dart analyze` では見つからない、未使用の public なクラス、メソッド、フィールドも対象に |
| 🧬 | **コード生成ライブラリに対応** — freezed / json_serializable / riverpod / auto_route / go_router / drift / hive 向けのプリセットを完備 |
| 🧪 | **テストからしか使われていないコードを検出** — `lib/` 配下にあり、同じパッケージのテストからしか参照されていないコードを検出 |
| 📉 | **段階的に導入可能** — ベースラインを作成すれば、既存の検出結果を残したまま、新たに増えたデッドコードだけを CI で検出可能に |
| 🩺 | **不要になった設定を確認** — `kareki doctor` で、対象がなくなった `ignore` 設定や suppression コメントを確認 |
| ⚙️ | **CI で使いやすい設計** — JSON 形式の出力、結果に応じた終了コード、環境に依存しないベースラインに対応 |

## What it finds

| ルール | 検出対象 |
|---|---|
| `unused_element` | ワークスペース内のどこからも使われていない public なクラス、関数、メソッド、getter、setter、フィールド、トップレベル変数、extension、extension type、typedef |
| `unused_file` | ほかのファイルから `import`、`part`、`export` されていない `.dart` ファイル |
| `unused_pub_dependency` | `pubspec.yaml` に記載されているものの、ソースコードから一度も import されていない依存パッケージ |
| `test_only_used` | `lib/` 配下にあり、テストコード（`*_test.dart`、`test/`、`integration_test/` 配下）からしか参照されていない public 宣言 |
| `unused_parameter` | 関数、メソッド、名前付きコンストラクタの本体や初期化処理で一度も参照されていない引数。Dart 標準の `unused_element_parameter` では検出できない必須引数や public API も対象です。 |
| `unused_parameter_optional` | ワークスペース内のどの呼び出し元からも値を渡されていない省略可能な引数（名前付き引数またはオプショナル位置引数）。単一ライブラリ内の private な省略可能引数だけを調べる Dart 標準の `unused_element_parameter` と異なり、public API やパッケージをまたぐ呼び出しも対象です。 |

## Install

```yaml
# pubspec.yaml
dev_dependencies:
  kareki: ^0.1.0
```

```sh
dart pub get
```

## Usage

ワークスペースのルートで、次のコマンドを実行します。

```sh
dart run kareki
```

オプションについては、[CLI reference](doc/cli.ja.md) を参照してください。

## Adopting on an existing codebase

最初からすべてのデッドコードを修正する必要はありません。現在の検出結果をベースラインとして保存しておけば、それ以降に増えたデッドコードだけを CI で検出できます。

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

詳しくは、[Baseline](doc/baseline.ja.md) を参照してください。

## Keeping the config honest

ファイルの移動や名前の変更、パッケージの削除を重ねると、除外設定や依存パッケージの許可リストに不要な項目が残ることがあります。`kareki doctor` を実行すると、現在のコードと一致しなくなった設定を確認できます。

```sh
dart run kareki doctor
```

詳しくは、[Doctor](doc/doctor.ja.md) を参照してください。

## Documentation

[ドキュメントサイト](https://ostk0069.github.io/kareki/ja/)から読むことも、Markdown の原文を直接読むこともできます。

- [CLI reference](doc/cli.ja.md) — コマンドの使い方、オプション、終了コード
- [Configuration](doc/configuration.ja.md) — `kareki-config.yaml` の書き方、プリセットや除外・抑制の設定方法
- [Baseline](doc/baseline.ja.md) — 現在の検出結果を保存し、新しく増えたデッドコードだけを検出する方法
- [Doctor](doc/doctor.ja.md) — 不要になった除外設定や抑制コメントを見つける方法
- [解析の仕組み](doc/how-it-works.ja.md) — デッドコードを検出する仕組み、エントリポイントの扱い、対応バージョン
- [運用のベストプラクティス](doc/operations.ja.md) — cronとAIエージェントで定期的にクリーンアップPRを作る方法

## License

MIT License です。詳しくは [LICENSE](LICENSE) を参照してください。

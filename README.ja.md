# kareki

[English](README.md) | **日本語**

<img width="1645" height="496" alt="header image" src="https://github.com/user-attachments/assets/dc3b1903-8ff1-4556-9d4e-ac847e3c8bd0" />

[![pub package](https://img.shields.io/pub/v/kareki.svg)](https://pub.dev/packages/kareki)
[![CI](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml/badge.svg)](https://github.com/ostk0069/kareki/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

> 枯木 (kareki): 剪定が必要な、生命を失った枝。

**Dart / Flutter のワークスペース全体を対象としたデッドコード検出ツール**です。`dart analyze` が単一パッケージ内の private な未使用宣言しか検出しないのに対し、`kareki` は Melos / pub workspace 全体にまたがる参照を解決し、気づかれないまま積もっていくデッドコード — 呼び出し元のない public API、どこからも import されていないファイル、宣言だけ残った pub 依存 — を洗い出します。

## Why kareki?

|  | 提供する価値 |
|---|---|
| 🌲 | **ワークスペース横断**。Melos / pub workspace 配下の全パッケージにまたがって参照を解決します。 |
| 🔓 | **public API も対象**。`dart analyze` が見落とす public なクラス・メソッド・フィールドも検出します。 |
| 🧬 | **コード生成に強い**。freezed / json_serializable / riverpod / auto_route / go_router / drift / hive のプリセットを同梱。 |
| 🧪 | **`test_only_used`**。`lib/` 配下で、自身のテストからしか使われていないコードを発見します。 |
| 📉 | **Baseline**。既存コードベースに後付け導入しても、CI が落ちるのは **新規の** 検出のみ。 |
| 🩺 | **Doctor**。`kareki doctor` が古くなった `ignore` 設定や、もう何も抑制していない suppression コメントを指摘します。 |
| ⚙️ | **CI 対応**。JSON 出力、決定的な終了コード、環境に依存しない baseline。 |

## What it finds

| ルール | 検出対象 |
|---|---|
| `unused_element` | ワークスペース内のどこからも呼ばれていない public なクラス / 関数 / メソッド / getter / setter / フィールド / トップレベル変数 / 拡張 / typedef。 |
| `unused_file` | 他のどのファイルからも `import` / `part` / `export` されていない `.dart` ファイル。 |
| `unused_pub_dependency` | `pubspec.yaml` に宣言されているがソース中で一度も import されていない依存パッケージ。 |
| `test_only_used` | `lib/` 配下で、テストコード（`*_test.dart`、`test/`・`integration_test/` 配下）からのみ参照されている public 宣言。 |
| `unused_parameter` | 関数 / メソッド / 名前付きコンストラクタが宣言しているが、本体や initializer のどこからも参照されていないパラメータ。public / private、required / optional すべてを対象とし、private な optional パラメータの未呼び出ししか検出しない Dart 標準の `unused_element_parameter` の上位互換です。除外: `@override` / abstract・external・native / operator / `this.x`・`super.x` / `_`・`__` プレースホルダ / 本体が `throw UnimplementedError(...)` だけのスタブ。typedef のシグネチャ制約で残しているコールバック引数は **flag されます** — `_` リネームで typedef 適合性を保ちつつ未使用を表明できます。 |

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

```sh
dart run kareki
```

詳細は [docs/cli.ja.md](docs/cli.ja.md) へ

## Adopting on an existing codebase

CI に組み込む前に全件修正しようとする必要はありません。現状をスナップショットしてコミットし、以降は **新規の** デッドコードだけで CI を落とすようにします。

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

詳細は [docs/baseline.ja.md](docs/baseline.ja.md) へ

## Keeping the config honest

ファイル除外や依存のホワイトリストは、ファイルの移動・改名やパッケージの削除によって、いつの間にか何も指していない設定になりがちです。`kareki doctor` は、もう実態とマッチしていない設定エントリを洗い出します。

```sh
dart run kareki doctor
```

詳細は [docs/doctor.ja.md](docs/doctor.ja.md) へ

## Documentation

- [CLI リファレンス](docs/cli.ja.md) — 全オプション、全終了コード
- [設定](docs/configuration.ja.md) — `kareki-config.yaml`、デフォルト、ビルトインプリセット、カスタムプリセット、抑制、完全な例
- [Baseline](docs/baseline.ja.md) — 段階的導入
- [Doctor](docs/doctor.ja.md) — 実態とズレた設定を検出
- [仕組み](docs/how-it-works.ja.md) — 解析パイプライン、エントリポイントの種出し、サポート対象バージョン

## License

MIT. See [LICENSE](LICENSE).

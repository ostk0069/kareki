---
title: 設定
weight: 3
---

`kareki` はワークスペースのルートにある `kareki-config.yaml` を読み込みます。すべてのキーは省略可能です。

## 設定項目

| キー | 型 | 用途 |
|---|---|---|
| `packages` | map | ワークスペースのパッケージ glob を上書き（デフォルトは melos.yaml / pub workspace から自動検出）。 |
| `exclude` | map | 指摘の対象から除外するファイル、宣言名、引数名。 |
| `entry_points` | map | 追加のエントリポイントとなるファイル / 宣言名。 |
| `keep_alive_annotations` | map | 有効化する組み込みプリセットと、追加で扱う keep-alive アノテーション名。 |
| `custom_presets` | map | プロジェクト独自のプリセット、または組み込みの上書き。 |
| `annotation_implied_packages` | map | プリセットとは別に指定する、アノテーションと pub パッケージの対応。 |
| `sdk_packages` | list | `unused_pub_dependency` でも決して指摘しないパッケージ（SDK 同梱）。 |
| `ignore` | map | グローバル / パッケージ単位の抑制。 |
| `output.format` | `text` \| `json` | デフォルトのレポート形式。 |
| `baseline` | path | ベースラインのパス（ワークスペースルートからの相対）。記録された指摘を出力から除外。 |

## デフォルト値

| 設定項目 | 組み込みの値 |
|---|---|
| `exclude.files` | `.g.dart`, `.freezed.dart`, `.gr.dart`, `.generated.dart`, `.drift.dart`, `.steps.dart`, `.pb.dart`, `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart`, `.pbgrpc.dart`, `.config.dart`, `l10n*.dart`, `*mocks.dart` |
| `entry_points.files` | `**/*.story.dart`, `**/widgetbook/**/*.dart` |
| `keep_alive_annotations.presets` | `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta` |
| `sdk_packages` | `flutter`, `flutter_test`, `flutter_driver`, `flutter_localizations`, `flutter_web_plugins`, `integration_test`, `sky_engine` |
| 暗黙のエントリポイント規約 | `main.dart` / `main_*.dart`、`flutter_test_config.dart`、`*_test.dart`（`test/` 配下）、`bin/`・`integration_test/`・`lib/l10n/` 配下の全ファイル、収集対象のうちトップレベル `main` を持つファイル |
| 生成ファイル判定（中身） | 冒頭に `GENERATED CODE - DO NOT MODIFY BY HAND` または `AUTO-GENERATED FILE. DO NOT EDIT` を含む |

## ソース収集と生成ファイル

各パッケージ直下の Dart ファイルと、`lib/`・`bin/`・`test/`・ `integration_test/`・`example/`・`tool/`・`tools/` 配下を収集します。 `build/`・`.dart_tool/`・`.git/` は探索せず、独立した探索対象として見つかった入れ子のパッケージは、親と重複させずそのパッケージ自身のソースとして収集します。収集されたトップレベル `main` を持つファイルは解析の起点になりますが、その他のスクリプト用ヘルパーは、使用が確認できなければ指摘します。 `entry_points.files` の指定だけでは、上記以外のディレクトリは収集されません。

`flutter: {generate: true}` のパッケージでは、`l10n.yaml` の `arb-dir`・ `output-dir`・`output-localization-file` と ARB 入力のロケールから Flutter gen-l10n の出力を認識します。既定値は `lib/l10n` と `app_localizations.dart` です。該当する出力だけを指摘対象外とし、そこからの参照・引数使用は引き続き解析します。ディレクトリ全体や同名に似たファイルを一律には除外しません。旧方式の `synthetic-package: true` による出力は、この判定の対象外です。生成処理自体は事前に実行してください。

`exclude.files` に一致するファイルも参照元として扱います。除外するのは指摘だけで、ソースの収集は続けます。Drift のスキーマスナップショットと `flutter_rust_bridge` の出力も、生成ツール固有のヘッダーで認識します。これらの import、参照、渡された引数も解析に含めます。

## 組み込みプリセット

| プリセット | keep-alive アノテーション | 暗黙的に必要となる pub パッケージ |
|---|---|---|
| `freezed` | `@freezed`, `@Freezed`, `@Default`, `@Assert` | `freezed_annotation`, `built_collection` |
| `json_serializable` | `@JsonSerializable`, `@JsonKey`, `@JsonEnum`, `@JsonValue` | `json_annotation` |
| `riverpod` | `@Riverpod`, `@riverpod` | `riverpod_annotation` |
| `auto_route` | `@AutoRouterConfig`, `@RoutePage`, `@AutoRoute`, `@CustomRoute`, `@MaterialRoute`, `@CupertinoRoute`, `@AdaptiveRoute` | — |
| `go_router` | `@TypedGoRoute`, `@TypedShellRoute`, `@TypedStatefulShellRoute`, `@TypedStatefulShellBranch` | `go_router` |
| `drift` | `@DriftDatabase`, `@DriftAccessor`, `@UseRowClass` | `drift` |
| `hive` | `@HiveType`, `@HiveField` | `hive` |
| `meta` *(常に有効)* | `@visibleForTesting`, `@visibleForOverriding`, `@protected`, `@internal`, `@immutable`, `@experimental`, `@mustCallSuper`, `@sealed`, `@factory`, `@useResult`, `@nonVirtual`, `@pragma` | `meta` |

定義は [`lib/src/preset/builtin_presets.dart`](https://github.com/ostk0069/kareki/blob/main/lib/src/preset/builtin_presets.dart) にあり、各項目には検証済みのフレームワークバージョン（`last_verified`）が記録されています。

### スキーマ生成に必要な宣言

組み込みの `drift` プリセットは、到達可能な `package:drift` の `Table` サブタイプについて、継承・mixin を含むカラム宣言を残します。生成された getter が上書きしていても、元の宣言は生成に必要です。未使用のテーブルや無関係な同名の型は、このルールでは残しません。

組み込みの `freezed` プリセットは、`package:freezed_annotation` の `Freezed` 型（`@freezed` を含む）で注釈された型のリダイレクトファクトリを残します。生成クラスを直接使う場合も、元のファクトリは生成する型の定義に必要です。

また、`.g.dart` part があり、アノテーションで JSON 変換の片方向でも設定が省略されている場合は、式本体の `fromJson` ファクトリを生成のスイッチとして残します。両方向の明示的な設定、ブロック本体、別名のファクトリ、無関係な同名アノテーションには、この追加ルールを適用しません。ビルド設定によってスイッチが不要な場合も、この判定では残します。

これらのプリセットを無効化・上書きすると、追加のスキーマ保護も無効になります。

## プリセットの追加・上書き

```yaml
custom_presets:
  # アノテーション名が異なるフォークに合わせて freezed を置き換える例。
  freezed:
    keep_alive_annotations: [freezed, Freezed]
    annotation_implied_packages:
      freezed: [freezed_annotation_v4]

  # 社内 DI コード生成のための新しいプリセットを追加する例。
  my_internal_di:
    keep_alive_annotations: [Injectable, Singleton]
    annotation_implied_packages:
      Injectable: [my_di_package]
      Singleton: [my_di_package]
```

`custom_presets.<name>` が組み込みと同じ名前のとき、組み込みの定義を完全に置き換えます。独自のアノテーションを使うフォークなどに対応できます。

## import 以外で使われる依存パッケージ

次の依存パッケージは、Dart の import がなくても使用中とみなします。

- 解決済みの `pubspec.yaml` に `ffiPlugin: true` または空でない `pluginClass` がある、Flutter のネイティブプラグイン。 Flutter が自動登録・同梱する場合があります。最も近い `.dart_tool/package_config.json` を使うため、事前に `pub get` を実行してください。すべてのプラットフォームで必要だと保証する判定ではありません。
- 各ソースに最も近い `analysis_options.yaml` が参照するパッケージ。相対パスと package の include を、参照先の include までたどります。
- 解決済みの Flutter `IconData` 定数、またはコンストラクタの `fontPackage` に文字列リテラルで指定されたフォントパッケージ。参照元のパッケージで使われているものとして扱います。

そのため、Flutter では依存パッケージだけの検査でも参照の解決が必要です。動的なアセットパスや任意のビルドスクリプトは推論しません。ビルド構成ごとに使うコードを削除する前に、[解析の仕組み](how-it-works.ja.md)の注意点を確認してください。

## 指摘の抑制

### ファイル単位（インライン）

```dart
// kareki: ignore_for_file=unused_element
```

```dart
// kareki: ignore_for_file=unused_element,unused_file
```

### 行単位（インライン）

`// kareki: ignore=<rule|name>` で単一行のみ抑制できます。単独行のコメントは「次の空行・コメント以外の行」を対象とし、行末コメントはその行自体を対象とします。

```dart
// kareki: ignore=unused_element
class Dead {}

class Other {} // kareki: ignore=unused_element

void foo({
  int? unused, // kareki: ignore=unused_parameter_optional
}) {}
```

複数のルールやシンボル名はカンマ区切りで指定できます:

```dart
// kareki: ignore=unused_element, MyClass
class MyClass {}
```

### パッケージごとの依存抑制

```yaml
ignore:
  dependencies:
    my_app:
      # kareki が解析できない独自のビルドスクリプトで使う依存。
      - custom_build_support
```

### グローバル

```yaml
ignore:
  packages: [legacy_tools]    # 指摘だけを抑制し、参照は残す
  rules: [unused_pub_dependency]
```

未使用引数のルールを有効に保ちつつ、ワークスペース全体で意図的に残す特定の引数名を許可するには、完全一致のリストを指定します:

```yaml
exclude:
  parameter_names: [context]
```

`exclude.parameter_names` が適用されるのは `unused_parameter` と `unused_parameter_optional` だけです。同名の宣言は抑制しません。現在の指摘を何も抑制していない項目は `kareki doctor` が報告します。

## 設定例

```yaml
version: 1

packages:
  include: ["packages/**", "modules/**", "."]
  exclude: ["**/build/**"]

exclude:
  files: ["**/*.fake.dart"]
  names: [debugFillProperties]
  parameter_names: [context]

entry_points:
  files: ["**/*.story.dart"]

keep_alive_annotations:
  presets: [freezed, riverpod, auto_route, json_serializable]
  custom: [KeepAlive]

custom_presets:
  my_internal_di:
    keep_alive_annotations: [Injectable]
    annotation_implied_packages:
      Injectable: [my_di_package]

ignore:
  packages: [my_lib_package]
  dependencies:
    my_app: [custom_build_support]

output:
  format: text
```

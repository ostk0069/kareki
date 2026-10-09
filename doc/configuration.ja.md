---
title: 設定
weight: 3
---

`kareki` はワークスペースのルートにある `kareki-config.yaml` を読み込みます。すべてのキーは省略可能で、デフォルトのままでも動作します。

## Top-level schema

| キー | 型 | 用途 |
|---|---|---|
| `packages` | map | ワークスペースのパッケージ glob を上書き（デフォルトは melos.yaml / pub workspace から自動検出）。 |
| `exclude` | map | 解析対象から除外するファイル、宣言名、引数名。 |
| `entry_points` | map | 追加のエントリポイントとなるファイル / 宣言名。 |
| `keep_alive_annotations` | map | 有効化するビルトインプリセットと、追加で扱う keep-alive アノテーション名。 |
| `custom_presets` | map | プロジェクト独自のプリセット、またはビルトインの上書き。 |
| `annotation_implied_packages` | map | スタンドアロンなアノテーション → pub パッケージのマッピング。 |
| `sdk_packages` | list | `unused_pub_dependency` でも決して指摘しないパッケージ（SDK 同梱）。 |
| `ignore` | map | グローバル / パッケージ単位の抑制。 |
| `output.format` | `text` \| `json` | デフォルトのレポート形式。 |
| `baseline` | path | baseline ファイルのパス（ワークスペースルートからの相対）。記録された検出は出力から抑制されます。 |

## Defaults

| 設定項目 | ビルトインの値 |
|---|---|
| `exclude.files` | `.g.dart`, `.freezed.dart`, `.gr.dart`, `.generated.dart`, `.pb.dart`, `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart`, `.pbgrpc.dart`, `.config.dart`, `l10n*.dart`, `*mocks.dart` |
| `entry_points.files` | `**/*.story.dart`, `**/widgetbook/**/*.dart` |
| `keep_alive_annotations.presets` | `freezed`, `json_serializable`, `riverpod`, `auto_route`, `go_router`, `drift`, `hive`, `meta` |
| `sdk_packages` | `flutter`, `flutter_test`, `flutter_driver`, `flutter_localizations`, `flutter_web_plugins`, `integration_test`, `sky_engine` |
| 暗黙のエントリポイント規約 | `main.dart` / `main_*.dart`、`flutter_test_config.dart`、`*_test.dart`（`test/` 配下）、`bin/`・`integration_test/`・`lib/l10n/` 配下の全ファイル、収集対象のうちトップレベル `main` を持つファイル |
| 生成ファイル判定（中身） | 先頭行に `GENERATED CODE - DO NOT MODIFY BY HAND` または `AUTO-GENERATED FILE. DO NOT EDIT` を含む |

## ソース収集と生成ファイル

各パッケージ直下の Dart ファイルと、`lib/`・`bin/`・`test/`・
`integration_test/`・`example/`・`tool/`・`tools/` 配下を収集します。
`build/`・`.dart_tool/`・`.git/` は探索せず、独立した探索対象として見つかった
入れ子のパッケージは、親と重複させずそのパッケージ自身のソースとして収集します。
収集されたトップレベル `main` を持つファイルは実行入口になりますが、
その他のスクリプト用ヘルパーは一律に保持しません。
`entry_points.files` の指定だけでは、上記以外のディレクトリは収集されません。

`flutter: {generate: true}` のパッケージでは、`l10n.yaml` の `arb-dir`・
`output-dir`・`output-localization-file` と ARB 入力のロケールから
Flutter gen-l10n の出力を認識します。既定値は `lib/l10n` と
`app_localizations.dart` です。該当する出力だけを指摘対象外とし、
そこからの参照・引数使用は引き続き解析します。ディレクトリ全体や
同名に似たファイルを一律には除外しません。旧方式の `synthetic-package: true`
はこの判定の対象外です。生成処理自体は事前に実行してください。

## Built-in presets

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

定義は [`lib/src/preset/builtin_presets.dart`](../lib/src/preset/builtin_presets.dart) にあり、各エントリには検証済みフレームワークバージョン（`last_verified`）が記録されています。

ビルトインの `freezed` プリセットは、実際の `package:freezed_annotation` の
`Freezed` 型のアノテーション（`@freezed` を含む）を確認し、その型の
リダイレクトファクトリを生成入力として保持します。生成クラスを直接使う場合も
元のファクトリは生成に必要です。`.g.dart` part があるライブラリでは、式本体の
`fromJson` ファクトリも JSON 生成のスイッチとして保持します。アノテーションで
`fromJson`・`toJson` の両方が明示されている場合、ブロック本体、別名のファクトリ、
別ライブラリの同名アノテーションは、この追加保護の対象外です。
ビルド設定でスイッチが不要になっている場合も、保守的に保持することがあります。
プリセットを無効化・上書きするとこの保護も外れます。

依存の使用には、各ソースに適用される `analysis_options.yaml` の相対・package
include と推移的な include、および解決済み Flutter `IconData` 定数やコンストラクタの
文字列リテラル `fontPackage` も含みます。フォント依存は参照元パッケージごとに判定し、
特定アプリ・パッケージ名の許可リストは使いません。Flutter の依存ルールのみの実行も
正常な依存解決が必要です。動的な資産パスや任意のビルドスクリプトは推論しません。

正規のトップレベル `main` の位置引数は実行環境から渡されるため、「一度も渡されない」
とは報告しません。関数本体で使っていない引数の検出は、別のルールとして維持します。

指摘は解析したソース構成に対するものです。FOSS 版などでビルド前にソースを差し替える
場合は、各構成の準備後に解析するか、入口ファイルを明示的に保持してください。
削除後にはコード生成・プロジェクトのテストも必要です。解析成功だけで実行時・各プラット
フォーム・解析外の利用者との互換性を保証するものではありません。

## Defining or overriding a preset

```yaml
custom_presets:
  # ビルトインの `freezed` プリセットを差し替えて、
  # アノテーション名が分岐しているフォークに固定する例。
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

`custom_presets.<name>` がビルトインと同じ名前のとき、ビルトインは **完全に置き換え** られます。アノテーション名が kareki のデフォルトと乖離した特定のフレームワークバージョンに固定したい場合に有用です。

## Suppression

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
      # Flutter ネイティブプラグインは自動登録されるため import されない。
      - geolocator_android
      - google_sign_in_ios
```

### グローバル

```yaml
ignore:
  packages: [dartx, wt_cli]    # これらのワークスペースパッケージをスキップ
  rules: [unused_pub_dependency]
```

未使用引数のルールを有効に保ちつつ、ワークスペース全体で意図的に残す
特定の引数名を許可するには、完全一致のリストを指定します:

```yaml
exclude:
  parameter_names: [context]
```

`exclude.parameter_names` が適用されるのは `unused_parameter` と
`unused_parameter_optional` だけです。同名の宣言は抑制しません。
現在の検出を何も抑制していないエントリは `kareki doctor` が報告します。

## Full example

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
    my_app: [geolocator_android, google_sign_in_ios]

output:
  format: text
```

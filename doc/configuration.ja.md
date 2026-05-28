# Configuration

[English](configuration.md) | **日本語**

`kareki` はワークスペースのルートにある `kareki-config.yaml` を読み込みます。すべてのキーは省略可能で、デフォルトのままでも動作します。

## Top-level schema

| キー | 型 | 用途 |
|---|---|---|
| `packages` | map | ワークスペースのパッケージ glob を上書き（デフォルトは melos.yaml / pub workspace から自動検出）。 |
| `exclude` | map | 解析対象から除外するファイル / 宣言名。 |
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
| 暗黙のエントリポイント規約 | `main.dart` / `main_*.dart`、`flutter_test_config.dart`、`*_test.dart`（`test/` 配下）、`bin/`・`integration_test/`・`lib/l10n/` 配下の全ファイル、`test/` 配下で `void main()` を宣言しているファイル |
| 生成ファイル判定（中身） | 先頭行に `GENERATED CODE - DO NOT MODIFY BY HAND` または `AUTO-GENERATED FILE. DO NOT EDIT` を含む |

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

## Full example

```yaml
version: 1

packages:
  include: ["packages/**", "modules/**", "."]
  exclude: ["**/build/**"]

exclude:
  files: ["**/*.fake.dart"]
  names: [debugFillProperties]

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

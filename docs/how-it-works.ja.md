# How it works

[English](how-it-works.md) | **日本語**

1. `melos.yaml` または pub workspace 経由でパッケージを検出する。
2. `package:analyzer` で全 `.dart` ファイルをパースし、宣言と外向きの simple-name 参照を抽出する。
3. エントリポイントを解決する（暗黙の規約、有効なプリセット、生成ファイル中の参照、設定の組み合わせ）。
4. simple-name グラフを、それらのルート識別子から BFS で辿る。
5. 到達できなかった宣言、参照されていないファイル、宣言されていない pub 依存を報告する。

## Entry-point seeding

エントリポイントは 4 つのレイヤから種出しされます。

| レイヤ | 出どころ |
|---|---|
| 暗黙 | Dart / Flutter SDK の規約（`main`、`_test`、`bin/`、`integration_test/`、`lib/l10n/`、`flutter_test_config.dart`）。 |
| ツール規約 | `entry_points.files` 設定（デフォルト: playbook / widgetbook 用の glob）。 |
| アノテーション | 有効なプリセットの keep-alive、`custom_presets.*.keep_alive_annotations`、`keep_alive_annotations.custom`。 |
| 生成コード | `exclude.files` にマッチするか `GENERATED CODE` ヘッダを持つファイル — それらの識別子参照が BFS のルートとして使われます。 |

このレイヤ構造により、コード生成を多用するエコシステムでも false positive を撒き散らさずに kareki を共存させられます。

## Supported versions

| コンポーネント | バージョン |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `^9.0.0` |

より新しい analyzer への対応は順次追加していきます。9.x に揃えているのは、analyzer 10+ に未移行のプロジェクトでも kareki を今すぐ採用できるようにするためです。

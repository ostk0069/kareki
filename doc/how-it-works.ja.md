---
title: 解析の仕組み
weight: 6
aliases:
  - /analysis-internals/
---

kareki は Dart / Flutter のワークスペース内の参照をたどり、使用が確認できないコードを検出します。このページは、Dart / Flutter のコードを読める方が、「なぜ指摘されたのか」「未使用に見えるのになぜ残るのか」「解析警告は何を判断できないという意味か」を理解するための説明です。コード例で解析を追い、結果を確認するときの注意点まで説明します。

## 解析の流れ

`example_app` というパッケージに次の 2 ファイルがあり、設定はデフォルトとします。以降の例でも、ファイル名のコメントでファイルを区切っています。

```dart
// lib/stores.dart
class LocalStore {
  void save() {}
}

class RemoteStore {
  void save() {}
}

// bin/main.dart
import 'package:example_app/stores.dart';

void main() => LocalStore().save();
```

1. **パッケージとファイルを探す。** ワークスペースと設定を読み、パッケージ直下のスクリプト、`lib/`、`bin/`、テスト、ツール用ディレクトリなどの対象ファイルを集めます。`--packages` は報告だけを絞ります。別パッケージが対象コードを呼んでいる可能性があるため、参照元の収集範囲は狭めません。
2. **宣言を集める。** クラス、メソッド、引数、import、抑制コメントなどを読み取ります。生成ファイルや除外ファイルも識別しますが、参照元としては残します。この時点で、二つの `save` は別々の宣言です。
3. **参照先を解決する。** Dart analyzer を使い、`LocalStore().save()` が `RemoteStore.save` ではなく `LocalStore.save` を指すと判断します。内部では、ライブラリ、ソースファイル、宣言位置、種別で区別します。依存先の欠落やソースのエラーで解決できなければ、名前だけの照合に切り替えず解析を止めます。
4. **参照を結び、起点からたどる。** 呼び出し元から宣言へ参照を結び、コンストラクター、所属する型、継承関係も補います。`main`、起点ファイル、設定したアノテーションなどからたどると、この例では `LocalStore` とその `save` に到達し、`RemoteStore` には到達しません。起点ファイル内の宣言はまとめて残す場合があるため、クラスを `bin/main.dart` に移すと結果が変わることもあります。
5. **ルールごとに判定する。** ほかに参照がなければ、`RemoteStore` と `RemoteStore.save` を `unused_element` で報告します。すべてのルールが同じ判定をするわけではなく、使う根拠は下表のように異なります。
6. **報告対象を絞る。** ルールや名前の除外、抑制コメント、パッケージの指定を適用し、CLI でベースラインを適用します。解析警告は指摘とは別の出力であり、追加の未使用ルールではありません。

## 判定の前提

### 解析する範囲と報告する範囲

`--packages` と `ignore.packages` は報告だけを絞り、探索した別パッケージからの参照は引き続き集めます。一方、`packages.exclude` はパッケージ自体を探索対象から外します。ソースの収集先や範囲の指定は[設定](configuration.ja.md)を参照してください。

### 解析の起点

解析の起点は、呼び出し元がなくても使用中とみなすコードです。次の 4 つから決めます。

| 種類 | 例 |
|---|---|
| Dart / Flutter の規約 | トップレベルの `main`、テストファイル、`bin/`、`integration_test/`、`lib/l10n/`、`flutter_test_config.dart`。 |
| 設定 | `entry_points.files` と `entry_points.names`。デフォルトのファイル指定は stories と widgetbook に対応します。 |
| アノテーション | 組み込み・独自のプリセットと、`keep_alive_annotations.custom`。 |
| 生成ファイル・除外ファイル | 未使用として報告しない場合も、その宣言と参照先を解析に含めます。 |

生成コードからの参照も考慮するため、生成元の宣言の誤検出を抑えられます。解析前にコード生成を実行してください。kareki 自体は不足しているファイルを生成しません。

明示的な `entry_points.names` の指定は、解決済みの呼び出しとは異なり、名前で照合します。

### 各ルールが使う根拠

上の例は、参照の解決が必要なルールを含む場合です。構文だけで判定できるルールのみなら、参照グラフの作成を省略します。

| ルール | 判定に使う根拠 |
|---|---|
| `unused_element` | 指摘対象の公開宣言に、いずれかの起点から到達できるか。 |
| `test_only_used` | テストの起点からは到達できるが、本番コードの起点からは到達できないか。 |
| `unused_parameter` | 関数の本体で引数を参照しているか。 |
| `unused_parameter_optional` | 呼び出し側が省略可能な引数を指定しているか。生成コードや未到達コードを含む全呼び出しを集計し、不明な呼び出し経路が残れば未使用とは断定しない。 |
| `unused_file` | 別の対象ファイルから import / export / part されているか、起点ファイルか。宣言への到達可能性とは別の判定。 |
| `unused_pub_dependency` | import と、対応するアノテーション、ビルド設定、ネイティブプラグイン、アセットからの利用。 |

### 省略可能な引数の使用状況

省略可能な引数は、生成コードや到達できないコードも含む、収集した全ソースの呼び出しから使用状況を調べます。実際のオーバーライドやリダイレクトファクトリの関係も考慮し、引数ごとに次の状態を区別します。

| 状態 | 意味 |
|---|---|
| 使用確認済み | 既知の呼び出しで値が渡されているか、対応する解析モデルで使用の可能性が確認できたため、残す必要があります。 |
| 解析範囲内で未指定 | 調べた呼び出しで値が渡されておらず、不明な呼び出し経路も残っていません。指摘の対象になります。 |
| 不明 | 安全に確認できない呼び出し経路があります。未使用とは判定しません。 |

正規のトップレベル `main` の位置引数は、実行環境から渡される場合があります。ただし、関数本体で使っていない引数を検出する別のルールからは除外しません。

## 判断が難しくなるケース

以下の「残す」は、未使用として報告しないという意味です。実行時に必ず使われると証明した、という意味ではありません。例にない呼び出しや抑制設定はないものとします。

### 1. dynamic な値では、同名メソッドのどれを呼ぶか分からない

```dart
// lib/stores.dart
class LocalStore {
  void save() {}
}

class RemoteStore {
  void save() {}
}

void persist(dynamic store) => store.save();

// bin/main.dart
import 'package:example_app/stores.dart';

void main() => persist(LocalStore());
```

**難しい理由：** `persist` の中では、レシーバーの静的な型が `dynamic` です。この呼び出しだけなら人間には `LocalStore` だと分かりますが、kareki は関数をまたいですべてのオブジェクトの受け渡しを追い、具体的な型を復元する解析は行っていません。

**kareki の扱い：** この呼び出しに到達できる場合、同名の `save` を持つ両方の候補を残し、`Unresolved reference "save"` という警告を出します。候補は「呼ばれる可能性がある宣言」であり、実際の呼び出し先と確定したわけではありません。最初の例のように参照先が解決できた場合とは、扱いが異なります。

**確認すること：** `persist` に渡される値をたどります。本当に `LocalStore` だけを受け取る API なら、型を明示すると参照先を解決できます。複数の型を受け取る必要がある API を、警告を消すためだけに狭めるべきではありません。

### 2. 保存されるコールバックでは、引数の渡され方を追いきれない

```dart
// lib/callbacks.dart
void save({bool force = false}) => print(force);

void Function()? pending;
void register(void Function() callback) {
  pending = callback;
}

// bin/main.dart
import 'package:example_app/callbacks.dart';

void main() {
  register(save);
  pending?.call();
}
```

**難しい理由：** `save` は関数そのものを値として渡され、保存された後に呼ばれます。`force` が一度も指定されないと断定するには、保存先からの読み出しや、その先への受け渡しをすべて追う必要があります。`void Function()` 型として受け取っても、元の関数から省略可能な引数がなくなるわけではありません。

**kareki の扱い：** この例では `force` を残し、引数の使用状況に関する警告を出します。本体では `force` を読んでいるため、これは `unused_parameter` ではなく `unused_parameter_optional` の判定に関する話です。一方、次のように同期的に直接呼ぶだけの受け取り先は、限定的に解析できます。

```dart
// lib/callbacks.dart
void save({bool force = false}) => print(force);

void runNow(void Function() callback) => callback();

// bin/main.dart
import 'package:example_app/callbacks.dart';

void main() => runNow(save);
```

受け取った引数の使い道が、`force` を指定しない直接呼び出しだけなので、ほかに利用がなければ `force` を `unused_parameter_optional` で報告します。保存、別の関数への転送、クロージャへの取り込みがあれば、この判定は使えません。一部の外部ライブラリでは保存されたコールバックから引数の使用を確認できますが、観測できなかった引数を未使用と断定するためには使いません。

**確認すること：** 登録箇所だけでなく、保存、転送、最終的な呼び出しまで確認します。`save(force: true)` のような呼び出しが見つかれば、別の経路が不明でも使用中と判断できます。ただし、人手で確認しただけでは kareki の判定は変わりません。

### 3. 条件付き export では、別の環境で必要なコードが選ばれる

```dart
// lib/backend.dart
export 'backend_stub.dart'
    if (dart.library.io) 'backend_io.dart';

// lib/backend_stub.dart
class Backend {
  String get name => 'stub';
}

// lib/backend_io.dart
class Backend {
  String get name => 'io';
}

// bin/main.dart
import 'package:example_app/backend.dart';

void main() => print(Backend().name);
```

**難しい理由：** 実行している環境で選ばれた `Backend` を解決できても、別の環境で他方の実装が必要かどうかは分かりません。ソースを解析することと、対応するすべての環境でビルドすることは別です。

**kareki の扱い：** このようにクラスを切り替える例では、分岐先の宣言を残し、条件付き import / export の警告を出します。引数なしの関数・getter だけで構成され、明示された戻り値の型が宣言単位で一致するような限定的な窓口では、一律に残す代わりに各分岐の宣言へ参照を結べます。ただし、それも各環境での実行時の正しさを証明するものではありません。

**確認すること：** 対応する全分岐を確認し、削除前に各環境のビルドやテストを行います。ビルドスクリプトがファイルを置き換える場合は、構成ごとにソースを準備して解析する必要があります。kareki 自体はそのスクリプトを実行しません。

### 4. JSON の戻り値は dynamic だが、任意の演算子を呼ぶとは限らない

```dart
// lib/lookup.dart
class Lookup {
  Object? operator [](String key) => readKey(key);
}

Object? readKey(String key) => key;

// bin/main.dart
import 'dart:convert';

void main() {
  final data = jsonDecode('{"name":"Ada"}');
  print(data['name'] as String);
}
```

**難しい理由：** `jsonDecode` の戻り値は `dynamic` です。`data['name']` の型だけを見ると、`Lookup.[]` のような独自の `[]` 演算子も呼び出し先の候補になります。一方、`jsonDecode` という名前だけでも判断できません。同名の別関数なら、任意のオブジェクトを返す可能性があるためです。

**kareki の扱い：** SDK のデコーダーであることと、戻り値の使われ方を確認します。この例は、書き換えずに値を読み、スカラー型へキャストするだけなので、`Lookup.[]` を呼びません。そのため `readKey` を使用中として残さず、未解決の `[]` に関する警告も出しません。`unused_element` は演算子そのものを報告しませんが、演算子から呼ぶ宣言は報告対象になり得ます。

戻り値を書き換えたり、別の処理へ渡したりすると、この限定的な判定は使えなくなります。例えば `bin/main.dart` を次の内容に置き換えます。

```dart
// bin/main.dart
import 'dart:convert';
import 'package:example_app/lookup.dart';

void main() {
  final data = jsonDecode('{}');
  data['nested'] = Lookup();
  print(data['nested']['name']);
}
```

この場合、コンテナの中にアプリ独自のオブジェクトが実際に入ります。kareki は候補の演算子から参照する `readKey` などを残し、警告を出します。

**確認すること：** 値の取得元だけでなく、後からの書き換えや受け渡しも確認します。JSONC・YAML にも同様の対応がありますが、レビュー済みの依存ソースとの一致が必要です。依存先の更新でこの扱いが無効になり、警告が再び出ることがあります。JSON の構造やキャストの成功を保証する判定ではありません。

### 5. 生成コードだけが参照している宣言もある

```dart
// lib/customer.dart
class Customer {
  String name = '';
}

// lib/customer.g.dart
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'customer.dart';

String generatedName(Customer customer) => customer.name;

// bin/main.dart
void main() {}
```

**難しい理由：** 生成ファイルを解析から丸ごと除くと、そこから手書きの宣言への参照が見えなくなります。手書きの呼び出しだけを探しても、`Customer.name` の利用は見つかりません。

**kareki の扱い：** 生成ファイル自身は指摘しませんが、その宣言と参照を起点として扱います。そのため、この例では `main` が `generatedName` を呼ばなくても `Customer` と `name` を残します。`exclude.files` に指定したファイルも同様です。指摘を増やすことより、必要かもしれないコードを残すことを優先した扱いです。

**確認すること：** 解析前にコードを再生成します。古い生成物が残っていると、古い参照も使用の根拠として残ります。逆に、生成物が欠けて参照を解決できなければ解析を止めます。結果を変えるために生成ファイルを直接編集するべきではありません。また、宣言を読み取っても通常の呼び出しを生成しないジェネレーターもあります。対応プリセットで扱えるものはありますが、任意のジェネレーターを解析できるわけではありません。

## 結果を確認するとき

指摘は**解析した範囲内で未使用**という意味です。範囲外の利用者や、解析していないビルド構成については別途確認が必要です。警告は判断できない部分を示すもので、削除すべき宣言の一覧でも、偽陽性と確定した結果でもありません。

警告にあるソース位置、参照先の候補、使用が未確認の引数を手掛かりに、上の該当ケースを調べます。判断できない間は対象コードを残してください。[doctor](doctor.ja.md) は解析警告が残る間、使用状況に依存する整理可否の検査を行いません。その状態で結果が空でも、問題なしとは判断できません。出力先と終了コードは [CLI リファレンス](cli.ja.md) を参照してください。

削除前に指摘と警告を確認し、削除後にはコード生成、静的解析、テスト、必要なビルドを実行してください。

## 対応バージョン

| コンポーネント | バージョン |
|---|---|
| Dart SDK | `>=3.10.0 <4.0.0` |
| analyzer | `>=10.2.0 <15.0.0` |

CI では、対応するすべての Dart マイナーバージョンと、最新の安定版 SDK で解析とテストを実行します。

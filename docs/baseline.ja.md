# Baseline

[English](baseline.md) | **日本語**

Baseline を使うと、既存の検出を一つひとつ消す前から kareki を導入できます。現状をスナップショットしてコミットしておけば、CI が落ちるのはそれ以降に発生した **新規の** 検出だけになります。

クリーンな作業ツリーの状態で baseline を生成します。

```sh
dart run kareki --baseline .kareki-baseline.json --write-baseline
```

これにより、現時点の全検出が `.kareki-baseline.json` に書き出されます。このファイルをコミットしておくと、以降同じ baseline を指し示して実行したとき（`--baseline` または `kareki-config.yaml` の `baseline: .kareki-baseline.json`）、一致する検出は出力と終了コードの両方から抑制されます。新規の検出があれば従来どおり失敗します。

ファイルは `(ruleId, stableId)` でソートされており、差分が読みやすい状態に保たれます。`stableId` に含まれる絶対パスは `<root>/` に置換されるため、マシンや CI チェックアウト先が変わっても可搬です。

修正が進んで baseline を縮めたくなったら、再生成するだけです。`dart run kareki --write-baseline`。

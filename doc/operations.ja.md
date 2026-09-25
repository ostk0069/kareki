---
title: 運用のベストプラクティス
weight: 7
---

`kareki` は、すべての commit や pull request を止めるゲートとして使うよりも、定期実行から AI エージェントを起動し、独立したクリーンアップ PR を作る運用に向いています。

## 推奨する運用

基本形は次のとおりです。

1. GitHub Actions を cron で起動する。
2. Workflow は AI エージェントを起動するだけにする。
3. AI エージェントがデフォルトブランチの最新状態で `kareki` を実行する。
4. 検出結果を確認し、安全に削除できるものだけを小さな単位で修正する。
5. format、analyze、test、`kareki` を実行してから PR を作る。
6. 人が通常のコードレビューを行ってマージする。

機能開発の PR とデッドコード削除を分離することで、開発者の待ち時間を増やさず、リポジトリ全体の検出結果をまとまった文脈で扱えます。

## PRごとに実行しない理由

`kareki` の検出対象は、変更されたファイルだけでなくワークスペース全体の参照関係です。そのため、ある PR で見つかった項目が、その PR によって生まれたとは限りません。

PRの必須チェックにすると、次の問題が起きやすくなります。

- 機能変更と関係のない既存の検出によってPRが止まる。
- 急いで通すための除外設定や抑制コメントが増える。
- 大きな削除が機能変更へ混ざり、レビューが難しくなる。
- リポジトリ全体の解析コストをすべてのcommitで負担する。

新しい検出を厳密に禁止したいチームは、[Baseline](../baseline/)を使ったPRチェックを追加できます。ただし、通常のクリーンアップは定期実行の別PRに分けることを推奨します。

## GitHub Actionsの例

次のWorkflowはcronからAIエージェントを起動します。

```yaml {filename=".github/workflows/kareki-cleanup.yml"}
name: "kareki: scheduled cleanup"

on:
  schedule:
    - cron: "0 0 * * *"
  workflow_dispatch:

concurrency:
  group: kareki-scheduled-cleanup
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  trigger-agent:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger the AI agent
        env:
          AI_AGENT_URL: ${{ secrets.AI_AGENT_URL }}
          AI_AGENT_TOKEN: ${{ secrets.AI_AGENT_TOKEN }}
        run: |
          curl --fail-with-body --retry 3 \
            -X POST "$AI_AGENT_URL" \
            -H "Authorization: Bearer $AI_AGENT_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"prompt":"Read .github/kareki-agent.md and perform the scheduled cleanup."}'
```

`AI_AGENT_URL` とリクエスト形式は、利用するAIサービスに合わせて変更してください。外部のGitHub AppがブランチとPRを作成する場合、Workflow自身には書き込み権限を与える必要はありません。

GitHub Actionsの `schedule` はデフォルトブランチの最新commitに対して実行されます。Workflowファイルもデフォルトブランチに存在する必要があります。詳細は[GitHub Actionsのscheduleドキュメント](https://docs.github.com/ja/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)を参照してください。

## AIエージェントへの指示

長い指示をWorkflow内のJSONへ埋め込まず、リポジトリ内のファイルとしてレビュー可能にしておくと運用しやすくなります。

```markdown {filename=".github/kareki-agent.md"}
# Scheduled kareki cleanup

1. デフォルトブランチの最新状態をcheckoutする。
2. 依存関係を取得し、ワークスペースルートで `dart run kareki --format json` を実行する。
3. 検出項目ごとに参照箇所を調査する。動的参照、コード生成、ルーティング、DI、シリアライズ、外部利用の可能性を確認する。
4. 安全性を説明できる項目だけを削除する。1つのPRを小さく保ち、無関係なリファクタリングを混ぜない。
5. `dart format`、`dart analyze`、関連テスト、`dart run kareki`、`dart run kareki doctor` を実行する。
6. 変更がある場合だけブランチをpushし、PRを作成する。変更がなければ何もしない。

## 制約

- デフォルトブランチへ直接pushしない。
- `kareki` を黙らせるためだけの除外や抑制を追加しない。
- 生成ファイルを直接編集しない。
- public APIや動的に参照されるコードは、未使用である根拠がない限り削除しない。
- テストが失敗した状態でPRを作成しない。

## PRに記載する内容

- 削除した項目と、安全に削除できると判断した根拠
- 実行した検証コマンドと結果
- 判断できずに残した検出項目
```

AIには「検出結果をすべて消す」ことではなく、「根拠を確認できた項目だけを修正する」ことを求めます。特にリフレクション、コード生成、文字列ベースのルーティング、DIコンテナ、プラグイン境界は静的な参照だけで判断しないでください。

## 導入時の目安

最初は1PRあたり数件から始めます。誤検出の傾向やレビュー負荷が分かってから、修正量を調整してください。

大量の既存検出がある場合は、先にBaselineを作成し、AIにはBaseline外の新しい検出または安全性の高いルールから対応させると段階的に導入できます。

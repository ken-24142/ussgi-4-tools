# CostDt — 月次利用料集計スクリプト

payer（AWS Organizations の管理）アカウントの **CloudShell** で実行するシェルスクリプトです。
組織配下の各メンバーアカウントについて、**前月** と **2か月前** のUSD利用料総額（`UnblendedCost`）を集計し、`CostOptimization/accounts.json` と同じ形式のJSONで出力します。

`CostOptimization` 配下のレポート生成Lambdaを使う運用において、毎月 `accounts.json` を手動更新するための補助ツールという位置づけです。

## 何をするか

```
       CloudShell (payerアカウント)
              │
              ▼
        ./costdt.sh
              │
              ├── aws organizations list-accounts
              │       └── ACTIVEなアカウント一覧を取得
              │
              ├── aws ce get-cost-and-usage  (× 2回, us-east-1)
              │       ├── 2か月前のLINKED_ACCOUNT別利用料
              │       └── 前月の  LINKED_ACCOUNT別利用料
              │
              └── 出力
                    ├── stderr: 集計結果の整形表（TOTAL付き）
                    └── stdout: accounts.json と同形式のJSON
```

## 前提

- **payerアカウントのCloudShell** で実行すること（管理アカウントの認証情報が必要）。
- CloudShellに同梱されている `aws` CLI v2 と `jq` を使用（追加インストール不要）。
- 実行ロール/ユーザーに以下のIAM権限が必要:

| アクション | 用途 |
|---|---|
| `organizations:ListAccounts` | 組織配下のアカウント一覧取得 |
| `ce:GetCostAndUsage` | Cost Explorerからの月次利用料取得（us-east-1） |

- 管理アカウントの **Billingコンソール → Account Settings** で「**IAMユーザー/ロールによる請求情報へのアクセス**」が有効化されていること（IAM経由でCEを叩く場合の前提）。

## 使い方

```bash
chmod +x costdt.sh

# 表を見つつJSONを標準出力に流す（標準的な使い方）
./costdt.sh

# JSONだけをファイルに保存（表はstderrに残る）
./costdt.sh > accounts.json
```

## 出力例

**標準エラー出力（表）:**

```
対象期間: 2か月前=2026-03, 前月=2026-04

[1/3] Organizations からアカウント一覧を取得中...
  -> 3 アカウント取得
[2/3] Cost Explorer から 2026-03 の利用料を取得中...
[3/3] Cost Explorer から 2026-04 の利用料を取得中...

==== 集計結果 ====
AccountID       Name                                             2026-03         2026-04
--------------  ----------------------------------------  --------------  --------------
111111111111    Production                                       1234.56         2345.67
222222222222    Staging                                           100.00          120.50
333333333333    Sandbox                                             0.00            0.00
--------------  ----------------------------------------  --------------  --------------
TOTAL                                                            1334.56         2466.17
```

**標準出力（JSON、`accounts.json` 形式）:**

```json
[
  {
    "id": "111111111111",
    "name": "Production",
    "cost_2_months_ago": 1234.56,
    "cost_prev_month": 2345.67
  },
  {
    "id": "222222222222",
    "name": "Staging",
    "cost_2_months_ago": 100.00,
    "cost_prev_month": 120.50
  },
  {
    "id": "333333333333",
    "name": "Sandbox",
    "cost_2_months_ago": 0,
    "cost_prev_month": 0
  }
]
```

## 推奨される運用フロー

1. 月初の自動レポート実行（`CostOptimization` のEventBridge Scheduler）の **前日まで** に、payerアカウントのCloudShellで `./costdt.sh > accounts.json` を実行。
2. 生成された `accounts.json` を、`CostOptimization` 用のS3バケットへ `aws s3 cp accounts.json s3://<bucket-name>/accounts.json` でアップロード。
3. Lambdaが自動実行されるとMarkdownレポートにコスト値が反映される。

## セキュリティ上の注意

> ⚠️ **出力JSONには実アカウントIDと実アカウント名が含まれます。**
> アカウント名はしばしば社名・用途・環境名を示すため、社内情報に該当します。
> 公開リポジトリへの誤コミット、SlackやGitHub Issueへの貼り付けなどに注意してください。

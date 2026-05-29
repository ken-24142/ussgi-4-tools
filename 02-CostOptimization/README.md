# AWS コスト最適化レポート生成

Cost Optimization Hub の API を Lambda で叩いて、AWSアカウントごとの「コスト最適化レポート」を Markdown ファイルとして S3 バケットに保存するTerraform構成です。
前月・2か月前の利用料は、Cost Explorerが委任管理者に対応していない都合上、`accounts.json` に手動で記入する運用です。

## アーキテクチャ

```
EventBridge Scheduler (毎月1日 09:00 JST)
        │
        ▼
     Lambda
        ├── S3 から accounts.json を取得
        │     （対象アカウント一覧 + 前月・2か月前の利用料）
        ├── Cost Optimization Hub: アカウント別の推奨施策 TOP3（削減額降順）
        └── S3 に Markdown レポートを書き込み
              s3://<bucket>/reports/YYYY-MM/<accountId>_<accountName>.md
```

## レポート項目

- AWSアカウント名
- AWSアカウントID
- レポート生成日
- 2か月前の利用料（USD、accounts.jsonに手動記入）
- 前月の利用料（USD、accounts.jsonに手動記入）
- 削減効果の大きい削減施策 最大3個
  - アクションタイプ / 対象リソース種別
  - 推奨ID
  - 対象リソース
  - リージョン
  - 期待される月間削減額

## 前提

本Lambdaを実行するAWSアカウントは、**Organizationsルート**、もしくは Organizationsルートから Cost Optimization Hub を委任された AWSアカウントである必要があります。

| 委任対象サービス | サービスプリンシパル |
|---|---|
| Cost Optimization Hub | `cost-optimization-hub.amazonaws.com` |

委任登録コマンド（Organizationsルートで実行）:

```bash
aws organizations register-delegated-administrator \
  --account-id <DELEGATED_ACCOUNT_ID> \
  --service-principal cost-optimization-hub.amazonaws.com
```

> **メモ**: 利用料の取得（Cost Explorer）は委任管理に対応していません。本構成では `accounts.json` に毎月手動で利用料を記入する運用としています。

その他:
- Terraform >= 1.14.1
- AWS CLI 設定済み（`aws configure`）
- Python と pip がローカルにインストール済み（zipビルドに使用）
- Windows + PowerShell で動作確認（`lambda.tf` の `local-exec` で PowerShell を使用）
- Cost Optimization Hub が有効化（Opt-in）されていること

## デプロイ手順

1. **Terraform backend の設定**
   `main.tf` の `backend "s3"` ブロックにある `bucket = "<bucket-name>"` を、ご自身のtfstate管理用S3バケット名に書き換えてください。
   または、`main.tf` を編集せずに `terraform init -backend-config="bucket=YOUR_BUCKET_NAME"` のように部分指定でもOKです。
2. `terraform init`
3. `terraform apply`
4. apply 完了後、S3バケット直下の `accounts.json` を実値に書き換える（後述）
5. 月初の自動実行を待つか、Lambda を手動 invoke してレポート生成を確認

## 対象アカウント一覧 (accounts.json) の設定

apply直後は以下のプレースホルダーが配置されています:

```json
[
  {
    "id": "123456789012",
    "name": "REPLACE_ME_SampleAccount",
    "cost_2_months_ago": 0,
    "cost_prev_month": 0
  }
]
```

これを実値に書き換えます。例:

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
  }
]
```

各フィールド:

| フィールド | 必須 | 内容 |
|---|---|---|
| `id` | はい | 対象アカウントID（12桁） |
| `name` | はい | レポートに表示するアカウント名 |
| `cost_2_months_ago` | 任意 | 2か月前の利用料（USD）。未指定/`null` の場合はレポートに `N/A` と出力 |
| `cost_prev_month` | 任意 | 前月の利用料（USD）。未指定/`null` の場合はレポートに `N/A` と出力 |

> **毎月の運用**: 月初の自動実行前に、管理アカウントの請求コンソール（または別途定期エクスポートしている請求データ）から前月/前々月の利用料を確認し、`accounts.json` の `cost_2_months_ago` / `cost_prev_month` の値を更新してからアップロードし直してください。

書き換え方法（どちらでもOK）:

- AWSマネジメントコンソール: S3バケット → `accounts.json` → 「編集」
- AWS CLI:
  ```bash
  aws s3 cp accounts.json s3://<bucket-name>/accounts.json
  ```

> Terraformの `aws_s3_object.accounts_json` は `lifecycle { ignore_changes = [content, ...] }` で保護されているため、後続の `terraform apply` でこのJSONが上書きされることはありません。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `main.tf` | Terraformブロック、provider、S3バケット、accounts.json初期配置 |
| `variables.tf` | region / project_name / schedule_expression 等の入力変数 |
| `outputs.tf` | Lambda関数名、S3バケット名、各種URI |
| `lambda.tf` | Lambdaビルド、IAMロール、Lambda関数 |
| `eventbridge.tf` | EventBridge Schedulerによる月次実行 |
| `lambda/index.py` | レポート生成本体（boto3） |
| `lambda/requirements.txt` | 依存パッケージ（今回は実質なし） |

## 注意点

- 利用料の値は `accounts.json` を手動更新する運用です。更新を忘れると、レポートには前回の値（または `N/A`）が出力されます。
- Cost Optimization Hub が未有効のアカウントについては推奨施策が空になります（エラーにはせずスキップ）。

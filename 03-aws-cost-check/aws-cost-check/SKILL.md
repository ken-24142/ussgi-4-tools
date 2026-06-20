---
name: aws-cost-check
description: 接続中のAWSアカウントを、コスト削減の主要10ポイントで実リソース構成からチェックする。Billing/Cost Explorerの権限が無くても、describe/list系のread-onlyだけで判定し、ポイントごとにレポートを出す。「コストチェックして」「AWSのコスト削減ポイント見て」「cost-check」などのときに使う。三層構造(EC2/ECS/ALB/Aurora MySQL)のSaaSを主な想定とする。
---

# AWS コスト最適化チェック

接続中のAWSアカウント（aws-mcp 経由）を、コスト削減の主要10ポイントで
**実際に作成されているリソース構成のみ**から判定し、ポイントごとにレポートする。

## 前提・方針
- **read-only に徹する**: `describe` / `list` / `get` 系のみ実行。作成・変更・削除は一切しない。
- **Billing 不要**: Cost Explorer / Billing 権限が無い前提。リソース構成だけで判定する。
- ロールが ReadOnlyAccess 等でも動くことが前提。権限エラーが出た項目は「権限不足で未確認」と明記する。
- 想定アーキテクチャ: EC2 / ECS / ALB / Aurora MySQL を中心とした三層構造 VPC の SaaS。

## 手順

### 1. 対象の確認
- `aws sts get-caller-identity` でアカウントID・ロールを確認。
- リージョンが不明なら、最初の describe 結果（VPCエンドポイントの ServiceName など）から判別するか、ユーザーに確認する。
- 複数リージョン運用の可能性があれば、対象リージョンをユーザーに確認する。

### 2. 各ポイントのリソース確認（read-only コマンド例）
独立した確認は並行実行してよい。

1. **Savings Plans / RI（コミット購入）**
   - `aws ec2 describe-reserved-instances`
   - `aws rds describe-reserved-db-instances`
   - `aws savingsplans describe-savings-plans`
   - `aws ec2 describe-instances`（稼働中ベースライン負荷の有無）
2. **Spot 活用** — `aws ecs list-clusters` / `aws ec2 describe-instances`（InstanceLifecycle で spot 判定）
3. **ライトサイジング（EC2/Fargate）** — `aws ec2 describe-instances`（InstanceType一覧。可能なら Compute Optimizer の所見）
4. **Aurora サイズ / I-O 最適化** — `aws rds describe-db-clusters` / `aws rds describe-db-instances`（StorageType が I/O-Optimized か、Serverless v2 か、リードレプリカ数）
5. **開発/ステージング自動停止** — instances/clusters のタグ（Env等）を見て、夜間停止候補を判定
6. **EBS/スナップショット/AMI 棚卸し** — `aws ec2 describe-volumes`（gp2残存・未アタッチ）/ `aws ec2 describe-snapshots --owner-ids self` / `aws ec2 describe-images --owners self`
7. **S3 ライフサイクル/ストレージクラス** — `aws s3api list-buckets`、各バケットに `aws s3api get-bucket-lifecycle-configuration`（NoSuchLifecycleConfiguration=未設定）
8. **データ転送費（NAT/VPC Endpoint）** — `aws ec2 describe-nat-gateways` / `aws ec2 describe-vpc-endpoints`（S3/ECR向け Gateway/Interface エンドポイントの有無）
9. **CloudWatch Logs 保持期間** — `aws logs describe-log-groups`（retentionInDays が未設定=無期限のものを抽出）
10. **不要リソース棚卸し（ゾンビ狩り）** — `aws elbv2 describe-load-balancers` / `aws elbv2 describe-target-groups` / `aws ec2 describe-addresses`（未アタッチEIP）/ `aws ecr describe-repositories`。
    削除済みリソースのロググループ残骸（例: 現存しない RDS クラスターの `/aws/rds/cluster/.../error`）も拾う。

### 3. レポート出力
- **ポイントごと**に結果を出す。凡例: ✅該当なし / ⚠️改善ポイントあり / 👍良好。
- 該当リソースが無い項目は「該当なし（対応不要）」と明記してよい（空アカウントでも省略しない）。
- ⚠️の項目には、対象リソースと具体的な推奨アクションを添える。
- 末尾に「該当なし / 改善あり / 良好」の区分まとめを置く。
- ユーザーが希望すれば `YYYYMMDD-cost-check-report.md` 形式でマークダウンファイルに保存する。

## 注意
- 丸数字（①②③）は使わない（環境依存で読みにくい）。`1.` 形式を使う。
- ファイル保存時は新規作成を基本とし、既存ファイルの上書きは必ず確認する。

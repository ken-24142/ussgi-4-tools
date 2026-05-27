# AWS What's New 要約 Slack通知

AWS What's NewのRSSを定期取得し、Bedrock (Amazon Nova Lite, Converse API経由) で要約してSlackに投稿するシンプルなTerraform構成です。

## アーキテクチャ

```
EventBridge Scheduler (毎時0分)
        │
        ▼
     Lambda ─── DynamoDB (処理済みentry_idで重複防止)
        │
        ├── Bedrock (要約)
        └── Slack (Block Kitで投稿)
```

## 投稿ルール（フィルタリング）

記事の**タイトル＋本文**を判定し、以下の **条件1と条件2を両方満たす場合のみ** Bedrockで要約します。
それ以外の記事は **タイトルとURLのみ** をSlackに投稿します（要約なし＝Bedrockを呼ばないのでコストも節約）。

- **条件1（東京リージョン または 全リージョン対象）**: `tokyo` / `ap-northeast-1` / `東京` / `all (AWS / commercial) Regions` / `すべてのリージョン` / `全リージョン` のいずれかを含む
- **条件2（対象サービス）**: 次のいずれかを含む
  - `EC2` / `ECS` / `ECR` / `VPC` / `Aurora` / `CloudFront` / `WAF` / `Security Hub` / `Route 53`（`route53`表記も可） / `ACM`（`Certificate Manager`表記も可）

| 記事の内容 | 投稿内容 |
|---|---|
| （東京 または 全リージョン）× 対象サービス（両方成立） | タイトル ＋ **AI要約** ＋ URL |
| どちらか一方のみ / どちらも無し | タイトル ＋ URL のみ |

判定キーワードは `lambda/index.py` の `REGION_PATTERNS` / `SERVICE_PATTERNS` で調整できます（大文字小文字は区別しません）。

## 前提

- Terraform >= 1.14.1
- AWS CLI 設定済み（`aws configure`）
- Python と pip がローカルにインストール済み（zipビルドに使用）
- Windows + PowerShell で動作確認（`lambda.tf` の `local-exec` で PowerShell を使用）

## Slack App 事前準備

1. https://api.slack.com/apps で新規Appを作成
2. **OAuth & Permissions** で以下のBot Token Scopeを付与
   - `chat:write`
   - `chat:write.public`（チャンネルにBotをinviteしない場合）
3. ワークスペースにインストールし、**Bot User OAuth Token** (`xoxb-...`) を控える
4. 投稿先チャンネルの **Channel ID** を控える（チャンネル名右クリック → リンクをコピーの末尾）

## デプロイ手順
- terraform apply
- apply後、SSM Parameter Store にマネコンから値を投入


## 注意点

初回は直近のRSSエントリ全件が投稿されるので注意。2回目以降はDynamoDBの重複防止で新着のみ投稿されます。

## 参考記事（感謝！）

https://zenn.dev/nnydtmg/articles/aws-whatsnew-slide-site-1

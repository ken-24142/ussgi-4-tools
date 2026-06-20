# ussgi-4-tools
ussgi for tools

## ツール一覧

| # | 名前 | 種別 | 概要 |
|---|---|---|---|
| 01 | [aws-whatsnew-notifier](01-aws-whatsnew-notifier/) | Terraform | AWS What's New を要約して Slack 通知 |
| 02 | [CostOptimization](02-CostOptimization/) | Terraform | コスト最適化系の構成 |
| 03 | [aws-cost-check](03-aws-cost-check/) | Claude Code Skill | AWSアカウントをコスト削減10ポイントで read-only チェック |
| 04 | [security-hub-report](04-security-hub-report/) | Claude Code Skill | Security Hub CSPM の Critical/High 失敗を集計しレポート生成 |

### Claude Code Skill（03 / 04）の使い方

各フォルダ内の Skill 本体フォルダ（例: `03-aws-cost-check/aws-cost-check/`）を、
`~/.claude/skills/` または `<対象リポジトリ>/.claude/skills/` に置いて Claude Code を再起動すれば使えます。
どちらも **aws-mcp（AWS MCP サーバー）への接続**と **AWS の read-only 権限**が前提です。詳細は各 README を参照してください。

# aws-cost-check （Claude Code Skill）

接続中のAWSアカウントを、**コスト削減の主要10ポイント**で実リソース構成からチェックする Claude Code 用 Skill です。
Billing / Cost Explorer の権限が無くても、`describe` / `list` / `get` 系の **read-only コマンドだけ**で判定し、ポイントごとにレポートを出します。三層構造（EC2 / ECS / ALB / Aurora MySQL）の SaaS を主な想定としています。

## 中身

```
03-aws-cost-check/
├── README.md            ← このファイル
└── aws-cost-check/
    └── SKILL.md         ← Skill本体（フロントマター付きマークダウン）
```

## 導入方法

`aws-cost-check/` フォルダごと、以下のいずれかに置くだけで使えます（置いたら Claude Code を再起動）。

- **個人用（どのプロジェクトでも使う）**
  - `~/.claude/skills/aws-cost-check/SKILL.md`
  - Windows: `C:\Users\<ユーザー名>\.claude\skills\aws-cost-check\SKILL.md`
- **チーム共有（おすすめ）**
  - `<対象リポジトリ>/.claude/skills/aws-cost-check/SKILL.md`
  - Git にコミット & push すれば、メンバーは `git pull` するだけで使えます。

## 前提（共有時の注意）

この Skill は **aws-mcp（AWS MCP サーバー）に依存**します。受け取った人の環境で以下が必要です。

1. aws-mcp が接続設定済みであること
2. AWS 認証が通っていて、`describe` / `list` / `get` 系の **read-only 権限**があること（ReadOnlyAccess 等でOK）

> SKILL.md にはアカウントID等の固有値はベタ書きしていないので、そのまま他アカウントでも動きます。
> 複数アカウントを回す場合は、各コマンドに `--profile <名前>` を付けて切り替えます（IAM Identity Center の sso-session 構成なら1回のログインで全プロファイルを回せます）。

## 使い方

Claude Code で次のように話しかけると起動します。

- 「コストチェックして」
- 「AWSのコスト削減ポイント見て」
- 「cost-check」

結果はポイントごとに `✅該当なし / ⚠️改善ポイントあり / 👍良好` で表示され、希望すれば `YYYYMMDD-cost-check-report.md` 形式で保存できます。

# security-hub-report （Claude Code Skill）

AWS Security Hub CSPM の **Critical / High の失敗（FAILED）項目**を集計し、各項目の対応方法を添えた **Markdown レポート**を生成する Claude Code 用 Skill です。

## 中身

```
04-security-hub-report/
├── README.md                 ← このファイル
└── security-hub-report/
    └── SKILL.md              ← Skill本体（フロントマター付きマークダウン）
```

## 導入方法

`security-hub-report/` フォルダごと、以下のいずれかに置くだけで使えます（置いたら Claude Code を再起動）。

- **個人用（どのプロジェクトでも使う）**
  - `~/.claude/skills/security-hub-report/SKILL.md`
  - Windows: `C:\Users\<ユーザー名>\.claude\skills\security-hub-report\SKILL.md`
- **チーム共有（おすすめ）**
  - `<対象リポジトリ>/.claude/skills/security-hub-report/SKILL.md`
  - Git にコミット & push すれば、メンバーは `git pull` するだけで使えます。

## 前提（共有時の注意）

この Skill は **aws-mcp（AWS MCP サーバー）に依存**します。受け取った人の環境で以下が必要です。

1. aws-mcp が接続設定済みであること
2. AWS 認証が通っていて、Security Hub の `GetFindings` を呼べる権限があること
3. 対象アカウントで Security Hub CSPM が有効になっていること

> 対象アカウント・リージョンは **実行時の接続先を自動判定**します（固定していません）。そのまま他アカウントでも動きます。

## 使い方

Claude Code で次のように話しかけると起動します。

- 「Security Hubの失敗をチェック」
- 「CSPMレポート作って」

取得条件は `ComplianceStatus=FAILED` / `RecordState=ACTIVE` / `WorkflowStatus∈{NEW,NOTIFIED}` / `SeverityLabel∈{CRITICAL,HIGH}` で、結果は `YYYYMMDD-SecurityHub-Report.md` として出力されます（Critical / High の一覧表＋各項目の対応方法付き）。

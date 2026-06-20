---
name: security-hub-report
description: AWS Security Hub CSPM の Critical/High の失敗（FAILED）項目を集計し、各項目の対応方法を添えた Markdown レポートを生成する。「Security Hubの失敗をチェック」「CSPMレポート作って」などのときに使う。
---

# Security Hub CSPM レポート生成

接続中の AWS アカウントについて、Security Hub CSPM の Critical / High の失敗項目を集計し、対応方法付きの Markdown レポートを作成する Skill。

## 前提
- AWS MCP サーバー（aws-mcp）が接続済みであること。
- 対象アカウント・リージョンは **実行時の接続先を自動判定**する（固定しない）。

## 手順

### 1. 失敗項目を取得する
`mcp__aws-mcp__aws___run_script` で以下を実行し、Critical / High それぞれを **全ページ取得**する。

```python
import json

async def get_all(severity):
    findings = []
    token = None
    while True:
        params = {
            "Filters": {
                "ComplianceStatus": [{"Value": "FAILED", "Comparison": "EQUALS"}],
                "RecordState": [{"Value": "ACTIVE", "Comparison": "EQUALS"}],
                "WorkflowStatus": [
                    {"Value": "NEW", "Comparison": "EQUALS"},
                    {"Value": "NOTIFIED", "Comparison": "EQUALS"},
                ],
                "SeverityLabel": [{"Value": severity, "Comparison": "EQUALS"}],
            },
            "MaxResults": 100,
        }
        if token:
            params["NextToken"] = token
        resp = await call_boto3(service_name="securityhub", operation_name="GetFindings", params=params)
        findings.extend(resp.get("Findings", []))
        token = resp.get("NextToken")
        if not token:
            break
    return findings

out = {}
for sev in ["CRITICAL", "HIGH"]:
    fs = await get_all(sev)
    rows = []
    for f in fs:
        res_ids = [r.get("Id") for r in f.get("Resources", []) if r.get("Id")]
        rows.append({"title": f.get("Title"), "resources": res_ids})
    out[sev] = {"count": len(fs), "rows": rows}

print(json.dumps(out, ensure_ascii=False, indent=2))
```

> 取得条件: `ComplianceStatus=FAILED` / `RecordState=ACTIVE` / `WorkflowStatus∈{NEW,NOTIFIED}` / `SeverityLabel∈{CRITICAL,HIGH}`

### 2. 一覧表を作る
- 番号は Critical = `C-01, C-02...`、High = `H-01, H-02...` 形式。
- 表の列は「# / 項目（Title） / リソース識別子」。
- リソース識別子は、`Resources[].Id` が **個別リソースのARN等のときのみ**記載する。
  `AWS::::Account:<AccountId>` のようなアカウント単位のものは「（アカウントレベル）」と表記する。

### 3. 対応方法を添える
各項目（C-xx / H-xx）に **短文1行**で対応方法を書く。
- 内容が重複・類似する項目は「H-xx と同じ」等でまとめてよい。
- 既知のコントロールの対応方法の例:
  - Inspector 各種スキャン → 「Amazon Inspector の 該当スキャンを有効化する」（まとめて有効化可）
  - GuardDuty → 「GuardDuty を有効化する」
  - AWS Config → 「AWS Config を有効化し、サービスリンクロールで記録開始」
  - Hardware MFA (root) → 「ルートユーザーにハードウェアMFAを設定する」
  - SSM public sharing block → 「SSMのパブリック共有ブロックを有効化する」
  - VPC default SG → 「デフォルトSGのイン/アウトバウンドルールを全削除する」
  - ECS logging → 「タスク定義に logConfiguration を設定する」
  - ECS readonly rootfs → 「タスク定義で readonlyRootFilesystem: true を設定する」
  - EBS snapshot public access → 「EBSスナップショットのパブリックアクセスブロックを有効化する」
  - 未知の項目は Title から妥当な対応を1行で要約する。

### 4. Markdown ファイルに出力する
- ファイル名: `YYYYMMDD-SecurityHub-Report.md`（YYYYMMDD は実行日）。
- 出力先はカレントの作業ディレクトリ。
- **既存ファイルの上書きは事前に確認する**（プロジェクトのルールに従う）。
- 構成:
  1. ヘッダー（作成日・対象アカウントID・取得条件・件数サマリ）
  2. Critical 一覧表
  3. High 一覧表
  4. 「【対応方法】」セクション（C-xx / H-xx ごとの短文）
  5. ワンポイント（あれば）

## 出力スタイル
- プロジェクトのキャラ設定（明るく元気・カジュアル）に従って、作業後は変更点を箇条書きで要約する。

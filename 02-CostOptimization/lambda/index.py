"""コスト最適化レポート生成 Lambda。

前提:
- 本Lambdaを実行するAWSアカウントは、Organizationsルート、または以下の委任管理者になっていること:
    - Cost Optimization Hub  (service principal: cost-optimization-hub.amazonaws.com)
- 対象アカウント一覧、および前月/前々月の利用料は、S3 上の accounts.json から読み取る
  （Cost Explorerは委任不可のため、利用料は手動でJSONに記入する運用）。
"""

import json
import logging
import os
import re
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

REPORT_BUCKET = os.environ["REPORT_BUCKET"]
ACCOUNTS_KEY = os.environ["ACCOUNTS_KEY"]
REPORTS_PREFIX = os.environ.get("REPORTS_PREFIX", "reports").rstrip("/")
MAX_RECOMMENDATIONS = int(os.environ.get("MAX_RECOMMENDATIONS", "3"))

s3 = boto3.client("s3")
# Cost Optimization Hub は us-east-1 のみのセンタライズドサービス。
coh = boto3.client("cost-optimization-hub", region_name="us-east-1")


def _to_optional_float(value) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        logger.warning("Invalid cost value in accounts.json: %r (treated as N/A)", value)
        return None


def load_accounts() -> list[dict]:
    """S3から対象アカウント一覧JSONを読み込む。

    期待フォーマット:
        [
            {
                "id": "123456789012",
                "name": "Production",
                "cost_2_months_ago": 1234.56,   # 任意。未指定/null可。
                "cost_prev_month":   2345.67    # 任意。未指定/null可。
            },
            ...
        ]
    """
    obj = s3.get_object(Bucket=REPORT_BUCKET, Key=ACCOUNTS_KEY)
    data = json.loads(obj["Body"].read())
    if not isinstance(data, list):
        raise ValueError(f"{ACCOUNTS_KEY} はJSON配列である必要があります。")
    accounts = []
    for item in data:
        if not isinstance(item, dict) or "id" not in item or "name" not in item:
            raise ValueError(f"accounts.json の各要素には id と name が必要です: {item}")
        accounts.append({
            "id": str(item["id"]),
            "name": str(item["name"]),
            "cost_2_months_ago": _to_optional_float(item.get("cost_2_months_ago")),
            "cost_prev_month": _to_optional_float(item.get("cost_prev_month")),
        })
    logger.info("Loaded %d accounts from s3://%s/%s", len(accounts), REPORT_BUCKET, ACCOUNTS_KEY)
    return accounts


def previous_months(today) -> tuple[tuple[int, int], tuple[int, int]]:
    """today から見た「前月」「2か月前」の (year, month) を返す。"""
    y, m = today.year, today.month
    # 前月
    prev_y, prev_m = (y - 1, 12) if m == 1 else (y, m - 1)
    # 2か月前
    if prev_m == 1:
        prev2_y, prev2_m = prev_y - 1, 12
    else:
        prev2_y, prev2_m = prev_y, prev_m - 1
    return (prev2_y, prev2_m), (prev_y, prev_m)


def fetch_top_recommendations(account_id: str, limit: int) -> list[dict]:
    """指定アカウントの推奨施策を、月間推定削減額の降順で最大 limit 件取得する。"""
    try:
        res = coh.list_recommendations(
            filter={"accountIds": [account_id]},
            orderBy={"dimension": "EstimatedMonthlySavings", "order": "Desc"},
            maxResults=limit,
        )
    except ClientError as e:
        # COH未有効、権限不足などをログに残してスキップ。
        logger.warning("ListRecommendations failed for %s: %s", account_id, e)
        return []
    items = res.get("items", [])
    return items[:limit]


# ファイル名やパスに使えない文字を除去・置換するためのパターン。
_SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9._\-]+")


def safe_filename(name: str) -> str:
    cleaned = _SAFE_NAME_RE.sub("_", name).strip("_")
    return cleaned or "account"


def format_amount(amount: float | None) -> str:
    if amount is None:
        return "N/A"
    return f"${amount:,.2f} USD"


def build_markdown(
    account: dict,
    report_month: tuple[int, int],
    cost_2_months_ago: float | None,
    cost_2_months_ago_label: str,
    cost_prev_month: float | None,
    cost_prev_month_label: str,
    recommendations: list[dict],
) -> str:
    today = datetime.now(timezone.utc).date().isoformat()
    lines: list[str] = []
    lines.append(f"# コスト最適化レポート - {account['name']}")
    lines.append("")
    lines.append(f"- **AWSアカウント名**: {account['name']}")
    lines.append(f"- **AWSアカウントID**: {account['id']}")
    lines.append(f"- **レポート生成日**: {today}")
    lines.append(f"- **2か月前の利用料 ({cost_2_months_ago_label})**: {format_amount(cost_2_months_ago)}")
    lines.append(f"- **前月の利用料 ({cost_prev_month_label})**: {format_amount(cost_prev_month)}")
    lines.append("")
    lines.append(f"## 削減効果の大きい削減施策 TOP{MAX_RECOMMENDATIONS}")
    lines.append("")

    if not recommendations:
        lines.append("- 推奨施策が見つかりませんでした（Cost Optimization Hub未有効、対象なし、または権限不足の可能性）。")
        lines.append("")
    else:
        for i, rec in enumerate(recommendations, start=1):
            title = (
                rec.get("recommendationLookupId")
                or rec.get("recommendationId")
                or "(no id)"
            )
            action_type = rec.get("actionType", "N/A")
            current_resource_type = rec.get("currentResourceType", "N/A")
            resource_id = rec.get("resourceId", "N/A")
            region = rec.get("region", "N/A")
            estimated_savings = rec.get("estimatedMonthlySavings")
            try:
                estimated_savings_str = format_amount(float(estimated_savings)) if estimated_savings is not None else "N/A"
            except (TypeError, ValueError):
                estimated_savings_str = str(estimated_savings)

            lines.append(f"### {i}. {action_type} - {current_resource_type}")
            lines.append(f"- **推奨ID**: {title}")
            lines.append(f"- **対象リソース**: `{resource_id}`")
            lines.append(f"- **リージョン**: {region}")
            lines.append(f"- **期待される月間削減額**: {estimated_savings_str}")
            lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("_本レポートはCost Optimization HubのAPI出力と手動入力の利用料データから自動生成されています。_")
    return "\n".join(lines)


def write_report_to_s3(year: int, month: int, account: dict, body: str) -> str:
    folder = f"{year:04d}-{month:02d}"
    filename = f"{account['id']}_{safe_filename(account['name'])}.md"
    key = f"{REPORTS_PREFIX}/{folder}/{filename}"
    s3.put_object(
        Bucket=REPORT_BUCKET,
        Key=key,
        Body=body.encode("utf-8"),
        ContentType="text/markdown; charset=utf-8",
    )
    return key


def lambda_handler(event, context):
    today = datetime.now(timezone.utc).date()
    (prev2_y, prev2_m), (prev_y, prev_m) = previous_months(today)
    prev2_label = f"{prev2_y:04d}-{prev2_m:02d}"
    prev_label = f"{prev_y:04d}-{prev_m:02d}"

    logger.info("Report target months: 2-months-ago=%s, prev=%s", prev2_label, prev_label)

    accounts = load_accounts()

    generated_keys: list[str] = []
    errors: list[str] = []

    for account in accounts:
        try:
            recs = fetch_top_recommendations(account["id"], MAX_RECOMMENDATIONS)
            body = build_markdown(
                account=account,
                report_month=(prev_y, prev_m),
                cost_2_months_ago=account["cost_2_months_ago"],
                cost_2_months_ago_label=prev2_label,
                cost_prev_month=account["cost_prev_month"],
                cost_prev_month_label=prev_label,
                recommendations=recs,
            )
            key = write_report_to_s3(prev_y, prev_m, account, body)
            generated_keys.append(key)
            logger.info("Wrote report: s3://%s/%s", REPORT_BUCKET, key)
        except Exception as e:
            logger.exception("Failed to generate report for %s: %s", account["id"], e)
            errors.append(f"{account['id']}: {e}")

    result = {
        "generated": len(generated_keys),
        "errors": len(errors),
        "keys": generated_keys,
        "errorDetails": errors,
    }
    logger.info("Done. %s", json.dumps(result, default=str))
    return result

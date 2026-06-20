#!/usr/bin/env bash
# costdt.sh
# payer (管理) アカウントの CloudShell で実行する集計スクリプト。
# 組織配下の各メンバーアカウントについて、前月と前々月のUSD利用料総額を取得する。
#
#   - 標準エラー出力: アカウント別の見やすい表
#   - 標準出力      : CostOptimization/accounts.json と同じ形式のJSON
#
# 使い方:
#   ./costdt.sh                  # 表を見て、JSONも標準出力に流す
#   ./costdt.sh > accounts.json  # JSONだけファイルに保存（表はstderrに残る）
#
# 必要なIAM権限:
#   - organizations:ListAccounts
#   - ce:GetCostAndUsage          (us-east-1 の Cost Explorer)
#
# ⚠️ 注意: 出力JSONには実アカウントIDとアカウント名が含まれます。
#         公開リポジトリ等への誤コミットに注意してください。

set -euo pipefail

# ---- 月境界の日付計算（YYYY-MM-01 / YYYY-MM 形式）----
THIS_MONTH_START=$(date -u +%Y-%m-01)
PREV_MONTH_START=$(date -u -d "${THIS_MONTH_START} -1 month" +%Y-%m-01)
PREV2_MONTH_START=$(date -u -d "${THIS_MONTH_START} -2 month" +%Y-%m-01)

PREV_LABEL=$(date -u -d "${PREV_MONTH_START}" +%Y-%m)
PREV2_LABEL=$(date -u -d "${PREV2_MONTH_START}" +%Y-%m)

echo "対象期間: 2か月前=${PREV2_LABEL}, 前月=${PREV_LABEL}" >&2
echo "" >&2

# ---- メンバーアカウント一覧（ACTIVE のみ）----
echo "[1/3] Organizations からアカウント一覧を取得中..." >&2
ACCOUNTS_JSON=$(aws organizations list-accounts \
  --query "Accounts[?Status=='ACTIVE'].{id:Id,name:Name}" \
  --output json)

ACCOUNT_COUNT=$(echo "${ACCOUNTS_JSON}" | jq 'length')
echo "  -> ${ACCOUNT_COUNT} アカウント取得" >&2

# ---- Cost Explorer 取得（ページング対応）----
# 引数: $1=Start (YYYY-MM-01), $2=End (YYYY-MM-01)
# 戻り値（stdout）: 全 Groups を結合したJSON配列
fetch_cost() {
  local start=$1
  local end=$2
  local all_groups="[]"
  local next_token=""
  local resp groups

  while :; do
    if [ -z "${next_token}" ]; then
      resp=$(aws ce get-cost-and-usage \
        --region us-east-1 \
        --time-period "Start=${start},End=${end}" \
        --granularity MONTHLY \
        --metrics UnblendedCost \
        --group-by Type=DIMENSION,Key=LINKED_ACCOUNT \
        --output json)
    else
      resp=$(aws ce get-cost-and-usage \
        --region us-east-1 \
        --time-period "Start=${start},End=${end}" \
        --granularity MONTHLY \
        --metrics UnblendedCost \
        --group-by Type=DIMENSION,Key=LINKED_ACCOUNT \
        --next-page-token "${next_token}" \
        --output json)
    fi

    groups=$(echo "${resp}" | jq '[.ResultsByTime[] | (.Groups // []) | .[]]')
    all_groups=$(jq -n --argjson a "${all_groups}" --argjson b "${groups}" '$a + $b')

    next_token=$(echo "${resp}" | jq -r '.NextPageToken // ""')
    [ -z "${next_token}" ] && break
  done

  echo "${all_groups}"
}

echo "[2/3] Cost Explorer から ${PREV2_LABEL} の利用料を取得中..." >&2
COST_2M=$(fetch_cost "${PREV2_MONTH_START}" "${PREV_MONTH_START}")

echo "[3/3] Cost Explorer から ${PREV_LABEL} の利用料を取得中..." >&2
COST_1M=$(fetch_cost "${PREV_MONTH_START}" "${THIS_MONTH_START}")

# ---- アカウント情報とコストを結合 ----
RESULT=$(jq -n \
  --argjson accounts "${ACCOUNTS_JSON}" \
  --argjson c2m "${COST_2M}" \
  --argjson c1m "${COST_1M}" '
  def amount($id; $groups):
    ([$groups[] | select(.Keys[0] == $id) | .Metrics.UnblendedCost.Amount | tonumber][0] // 0);
  def round2: (. * 100 | round) / 100;
  $accounts
  | sort_by(.name)
  | map({
      id: .id,
      name: .name,
      cost_2_months_ago: (amount(.id; $c2m) | round2),
      cost_prev_month:   (amount(.id; $c1m) | round2)
    })')

# ---- 表を標準エラーに出力 ----
echo "" >&2
echo "==== 集計結果 ====" >&2
printf "%-14s  %-40s  %14s  %14s\n" "AccountID" "Name" "${PREV2_LABEL}" "${PREV_LABEL}" >&2
printf "%-14s  %-40s  %14s  %14s\n" \
  "--------------" "----------------------------------------" "--------------" "--------------" >&2
echo "${RESULT}" | jq -r '.[] | [.id, .name, .cost_2_months_ago, .cost_prev_month] | @tsv' \
  | while IFS=$'\t' read -r id name c2m c1m; do
      printf "%-14s  %-40s  %14.2f  %14.2f\n" "${id}" "${name}" "${c2m}" "${c1m}" >&2
    done

# 合計行
TOTAL_2M=$(echo "${RESULT}" | jq '[.[].cost_2_months_ago] | add | (. * 100 | round) / 100')
TOTAL_1M=$(echo "${RESULT}" | jq '[.[].cost_prev_month] | add | (. * 100 | round) / 100')
printf "%-14s  %-40s  %14s  %14s\n" \
  "--------------" "----------------------------------------" "--------------" "--------------" >&2
printf "%-14s  %-40s  %14.2f  %14.2f\n" "TOTAL" "" "${TOTAL_2M}" "${TOTAL_1M}" >&2
echo "" >&2

# ---- JSONを標準出力へ ----
echo "${RESULT}"

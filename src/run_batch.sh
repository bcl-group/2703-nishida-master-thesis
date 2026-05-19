#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-/Users/rikunishida114/Desktop/rl/SB/bin/python}"
RUN_NOTEBOOK_SCRIPT="${RUN_NOTEBOOK_SCRIPT:-${PROJECT_ROOT}/run_notebook.sh}"
EVAL_SCRIPT="${EVAL_SCRIPT:-${PROJECT_ROOT}/evaluate_latest_run.py}"
PLOT_SCRIPT="${PLOT_SCRIPT:-${PROJECT_ROOT}/plot_batch_results.py}"
CURRENT_CONFIG_PATH="${CURRENT_CONFIG_PATH:-${PROJECT_ROOT}/current_run_config.json}"

POLL_SECONDS="${POLL_SECONDS:-5}"
TMP_OUTPUT_NOTEBOOK="${TMP_OUTPUT_NOTEBOOK:-${PROJECT_ROOT}/codex_runtime/.tmp_executed.ipynb}"

usage() {
  echo "Usage: $0 <config_dir>" >&2
  echo "Example: $0 configs/batch_2026_05_15_01" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

CONFIG_DIR="$1"
if [[ ! -d "${CONFIG_DIR}" ]]; then
  echo "[run_batch] config dir not found: ${CONFIG_DIR}" >&2
  exit 1
fi

CONFIG_DIR_ABS="$(cd "$(dirname "${CONFIG_DIR}")" && pwd)/$(basename "${CONFIG_DIR}")"
BATCH_ID="$(basename "${CONFIG_DIR_ABS}")"

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "[run_batch] python not found: ${PYTHON_BIN}" >&2
  exit 1
fi

if [[ ! -x "${RUN_NOTEBOOK_SCRIPT}" ]]; then
  echo "[run_batch] run_notebook.sh not found or not executable: ${RUN_NOTEBOOK_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${EVAL_SCRIPT}" ]]; then
  echo "[run_batch] evaluate_latest_run.py not found: ${EVAL_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${PLOT_SCRIPT}" ]]; then
  echo "[run_batch] plot_batch_results.py not found: ${PLOT_SCRIPT}" >&2
  exit 1
fi

RUNS_BATCH_DIR="${PROJECT_ROOT}/runs/${BATCH_ID}"
BATCH_RESULTS_DIR="${PROJECT_ROOT}/batch_results"
BATCH_OUTPUT_DIR="${BATCH_RESULTS_DIR}/${BATCH_ID}"
LOGS_ROOT="${PROJECT_ROOT}/logs"

mkdir -p \
  "${RUNS_BATCH_DIR}" \
  "${BATCH_RESULTS_DIR}" \
  "${BATCH_OUTPUT_DIR}" \
  "${LOGS_ROOT}" \
  "${PROJECT_ROOT}/codex_runtime"

SUMMARY_CSV="${BATCH_OUTPUT_DIR}/summary.csv"
SUMMARY_MD="${BATCH_OUTPUT_DIR}/summary.md"
BATCH_MANIFEST="${BATCH_OUTPUT_DIR}/batch_manifest.json"
PLOTS_PDF="${BATCH_OUTPUT_DIR}/${BATCH_ID}_plots.pdf"

echo "candidate_id,notebook_status,evaluation_status,latest_log_dir,success_rate_1000,success_rate_100,success_rate_all,peak_count,peak_time_ratio,gauss_center_error,gauss_rmse,gauss_r2,path_length_ratio,mean_total_reward_1000,mean_total_reward_100,last_eval_mean_reward,last_eval_mean_ep_length" > "${SUMMARY_CSV}"

candidate_count=0
failed_count=0
BATCH_STARTED_AT="$(date '+%F %T')"

pick_new_log_dir_from_snapshot() {
  local snapshot_file="$1"
  "${PYTHON_BIN}" - "${snapshot_file}" "${LOGS_ROOT}" <<'PY'
import sys
from pathlib import Path

snapshot_file = Path(sys.argv[1])
logs_root = Path(sys.argv[2])

before = set()
if snapshot_file.exists():
    before = {
        line.strip()
        for line in snapshot_file.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }

if not logs_root.exists():
    print("")
    raise SystemExit(0)

dirs = [p for p in logs_root.iterdir() if p.is_dir()]
new_dirs = [p for p in dirs if str(p) not in before]

if new_dirs:
    latest = max(new_dirs, key=lambda p: p.stat().st_mtime)
    print(latest)
else:
    print("")
PY
}

append_summary_row() {
  local manifest_json="$1"
  local iteration_summary_json="$2"

  "${PYTHON_BIN}" - "${SUMMARY_CSV}" "${manifest_json}" "${iteration_summary_json}" <<'PY'
import csv
import json
import sys
from pathlib import Path

summary_csv = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
iteration_summary_path = Path(sys.argv[3])

manifest = {}
if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

iteration = {}
if iteration_summary_path.exists():
    iteration = json.loads(iteration_summary_path.read_text(encoding="utf-8"))

row = [
    manifest.get("candidate_id", ""),
    manifest.get("notebook_status", ""),
    manifest.get("evaluation_status", ""),
    manifest.get("latest_log_dir", ""),
    iteration.get("success_rate_1000", ""),
    iteration.get("success_rate_100", ""),
    iteration.get("success_rate_all", ""),
    iteration.get("peak_count", ""),
    iteration.get("peak_time_ratio", ""),
    iteration.get("gauss_center_error", ""),
    iteration.get("gauss_rmse", ""),
    iteration.get("gauss_r2", ""),
    iteration.get("path_length_ratio", ""),
    iteration.get("mean_total_reward_1000", ""),
    iteration.get("mean_total_reward_100", ""),
    iteration.get("last_eval_mean_reward", ""),
    iteration.get("last_eval_mean_ep_length", ""),
]

with summary_csv.open("a", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(row)
PY
}

for CONFIG_JSON in "${CONFIG_DIR_ABS}"/candidate_*.json; do
  if [[ ! -e "${CONFIG_JSON}" ]]; then
    continue
  fi

  candidate_count=$((candidate_count + 1))

  CONFIG_JSON_ABS="$(cd "$(dirname "${CONFIG_JSON}")" && pwd)/$(basename "${CONFIG_JSON}")"
  CANDIDATE_ID="$(basename "${CONFIG_JSON_ABS}" .json)"
  RUN_DIR="${RUNS_BATCH_DIR}/${CANDIDATE_ID}"

  mkdir -p "${RUN_DIR}"
  rm -f \
    "${RUN_DIR}/codex_iteration_summary.json" \
    "${RUN_DIR}/evaluate_stdout.txt" \
    "${RUN_DIR}/executed.error.md" \
    "${RUN_DIR}/executed.error.json" \
    "${RUN_DIR}/logs_source"

  echo
  echo "=================================================="
  echo "[run_batch] running ${CANDIDATE_ID}"
  echo "=================================================="

  SNAPSHOT_FILE="$(mktemp)"
  find "${LOGS_ROOT}" -mindepth 1 -maxdepth 1 -type d > "${SNAPSHOT_FILE}" 2>/dev/null || true

  cp "${CONFIG_JSON_ABS}" "${CURRENT_CONFIG_PATH}"
  cp "${CONFIG_JSON_ABS}" "${RUN_DIR}/config_used.json"

  rm -f "${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.error.md"
  rm -f "${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.error.json"
  rm -f "${TMP_OUTPUT_NOTEBOOK}"

  STARTED_AT="$(date '+%F %T')"

  LAUNCH_OUT="${RUN_DIR}/run_notebook_stdout.txt"
  LAUNCH_STATUS=0
  if ! OUTPUT_NOTEBOOK="${TMP_OUTPUT_NOTEBOOK}" bash "${RUN_NOTEBOOK_SCRIPT}" > "${LAUNCH_OUT}" 2>&1; then
    LAUNCH_STATUS=$?
  fi

  PID="$(sed -n 's/^\[run_notebook\] pid        : //p' "${LAUNCH_OUT}" | tail -n 1)"
  LOG_PATH="$(sed -n 's/^\[run_notebook\] log        : //p' "${LAUNCH_OUT}" | tail -n 1)"
  META_PATH="$(sed -n 's/^\[run_notebook\] meta       : //p' "${LAUNCH_OUT}" | tail -n 1)"

  NOTEBOOK_STATUS="unknown"

  if [[ -z "${LOG_PATH}" || ! -f "${LOG_PATH}" ]]; then
    NOTEBOOK_STATUS="launch_failed_no_log"
  else
    while true; do
      if grep -q '\[execute_notebook\] success:' "${LOG_PATH}"; then
        NOTEBOOK_STATUS="success"
        break
      fi

      if grep -q '\[execute_notebook\] failed:' "${LOG_PATH}"; then
        NOTEBOOK_STATUS="failed"
        break
      fi

      if [[ -n "${PID}" ]]; then
        if ! kill -0 "${PID}" 2>/dev/null; then
          NOTEBOOK_STATUS="died_without_sentinel"
          break
        fi
      fi

      sleep "${POLL_SECONDS}"
    done
  fi

  LATEST_LOG_DIR="$(pick_new_log_dir_from_snapshot "${SNAPSHOT_FILE}")"

  EVAL_STATUS="not_run"
  EVAL_STDOUT="${RUN_DIR}/evaluate_stdout.txt"

  if [[ "${NOTEBOOK_STATUS}" == "success" ]]; then
    if "${PYTHON_BIN}" "${EVAL_SCRIPT}" --target final > "${EVAL_STDOUT}" 2>&1; then
      EVAL_STATUS="success"
    else
      EVAL_STATUS="failed"
    fi
  fi

  if [[ -n "${LATEST_LOG_DIR}" && -d "${LATEST_LOG_DIR}" ]]; then
    rm -f "${RUN_DIR}/logs_source"
    ln -s "${LATEST_LOG_DIR}" "${RUN_DIR}/logs_source"

    if [[ -f "${LATEST_LOG_DIR}/codex_iteration_summary.json" ]]; then
      cp "${LATEST_LOG_DIR}/codex_iteration_summary.json" "${RUN_DIR}/codex_iteration_summary.json"
    fi
  fi

  if [[ -f "${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.error.md" ]]; then
    cp "${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.error.md" "${RUN_DIR}/executed.error.md"
  fi

  if [[ -f "${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.error.json" ]]; then
    cp "${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.error.json" "${RUN_DIR}/executed.error.json"
  fi

  FINISHED_AT="$(date '+%F %T')"

  cat > "${RUN_DIR}/run_manifest.json" <<EOF
{
  "batch_id": "${BATCH_ID}",
  "candidate_id": "${CANDIDATE_ID}",
  "config_json": "${CONFIG_JSON_ABS}",
  "current_run_config_path": "${CURRENT_CONFIG_PATH}",
  "run_dir": "${RUN_DIR}",
  "started_at": "${STARTED_AT}",
  "finished_at": "${FINISHED_AT}",
  "launch_status_code": "${LAUNCH_STATUS}",
  "notebook_status": "${NOTEBOOK_STATUS}",
  "evaluation_status": "${EVAL_STATUS}",
  "pid": "${PID}",
  "log_path": "${LOG_PATH}",
  "meta_path": "${META_PATH}",
  "latest_log_dir": "${LATEST_LOG_DIR}"
}
EOF

  append_summary_row "${RUN_DIR}/run_manifest.json" "${RUN_DIR}/codex_iteration_summary.json"

  if [[ "${NOTEBOOK_STATUS}" != "success" || "${EVAL_STATUS}" != "success" ]]; then
    failed_count=$((failed_count + 1))
  fi

  echo "[run_batch] candidate_id    : ${CANDIDATE_ID}"
  echo "[run_batch] notebook_status : ${NOTEBOOK_STATUS}"
  echo "[run_batch] evaluation      : ${EVAL_STATUS}"
  echo "[run_batch] latest_log_dir  : ${LATEST_LOG_DIR}"
  echo "[run_batch] run_dir         : ${RUN_DIR}"

  rm -f "${SNAPSHOT_FILE}"
done

if [[ "${candidate_count}" -eq 0 ]]; then
  echo "[run_batch] no candidate_*.json found under ${CONFIG_DIR_ABS}" >&2
  exit 1
fi

"${PYTHON_BIN}" - "${SUMMARY_CSV}" "${SUMMARY_MD}" "${BATCH_ID}" <<'PY'
import csv
import sys
from pathlib import Path

summary_csv = Path(sys.argv[1])
summary_md = Path(sys.argv[2])
batch_id = sys.argv[3]

rows = []
with summary_csv.open("r", encoding="utf-8", newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

lines = []
lines.append(f"# Batch summary: {batch_id}")
lines.append("")
lines.append("| candidate | notebook | eval | success_rate_1000 | success_rate_100 | success_rate_all | peak_count | peak_time_ratio | gauss_center_error | gauss_rmse | gauss_r2 | path_length_ratio | mean_total_reward_1000 | mean_total_reward_100 | last_eval_mean_reward | last_eval_mean_ep_length |")
lines.append("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

for r in rows:
    lines.append(
        f"| {r['candidate_id']} | {r['notebook_status']} | {r['evaluation_status']} | "
        f"{r['success_rate_1000']} | {r['success_rate_100']} | {r['success_rate_all']} | "
        f"{r['peak_count']} | {r['peak_time_ratio']} | {r['gauss_center_error']} | "
        f"{r['gauss_rmse']} | {r['gauss_r2']} | {r['path_length_ratio']} | "
        f"{r['mean_total_reward_1000']} | {r['mean_total_reward_100']} | "
        f"{r['last_eval_mean_reward']} | {r['last_eval_mean_ep_length']} |"
    )

summary_md.write_text("\n".join(lines), encoding="utf-8")
PY

if "${PYTHON_BIN}" "${PLOT_SCRIPT}" \
  --summary_csv "${SUMMARY_CSV}" \
  --batch_id "${BATCH_ID}" \
  --output_dir "${BATCH_OUTPUT_DIR}"; then
  echo "[run_batch] plot generation: success"
else
  echo "[run_batch] plot generation: failed" >&2
fi

if "${PYTHON_BIN}" - "${BATCH_OUTPUT_DIR}" "${PLOTS_PDF}" <<'PY'
import sys
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

plot_dir = Path(sys.argv[1])
pdf_path = Path(sys.argv[2])

png_order = [
    "success_rates.png",
    "peak_count.png",
    "peak_time_ratio.png",
    "gauss_center_error.png",
    "gauss_rmse.png",
    "gauss_r2.png",
    "path_length_ratio.png",
    "reward_metrics.png",
    "eval_length.png",
]

existing = [plot_dir / name for name in png_order if (plot_dir / name).exists()]

if not existing:
    raise SystemExit(1)

with PdfPages(pdf_path) as pdf:
    for img_path in existing:
        img = plt.imread(img_path)
        fig = plt.figure(figsize=(11.69, 8.27))
        ax = fig.add_axes([0, 0, 1, 1])
        ax.imshow(img)
        ax.axis("off")
        pdf.savefig(fig, bbox_inches="tight", pad_inches=0)
        plt.close(fig)

print(f"[run_batch] plots pdf saved: {pdf_path}")
PY
then
  echo "[run_batch] plot pdf generation: success"
else
  echo "[run_batch] plot pdf generation: failed" >&2
fi

BATCH_FINISHED_AT="$(date '+%F %T')"

cat > "${BATCH_MANIFEST}" <<EOF
{
  "batch_id": "${BATCH_ID}",
  "config_dir": "${CONFIG_DIR_ABS}",
  "runs_dir": "${RUNS_BATCH_DIR}",
  "summary_csv": "${SUMMARY_CSV}",
  "summary_md": "${SUMMARY_MD}",
  "plot_dir": "${BATCH_OUTPUT_DIR}",
  "plots_pdf": "${PLOTS_PDF}",
  "candidate_count": "${candidate_count}",
  "failed_count": "${failed_count}",
  "started_at": "${BATCH_STARTED_AT}",
  "finished_at": "${BATCH_FINISHED_AT}"
}
EOF

echo
echo "[run_batch] batch_id      : ${BATCH_ID}"
echo "[run_batch] candidate_cnt : ${candidate_count}"
echo "[run_batch] failed_cnt    : ${failed_count}"
echo "[run_batch] summary_csv   : ${SUMMARY_CSV}"
echo "[run_batch] summary_md    : ${SUMMARY_MD}"
echo "[run_batch] plot_dir      : ${BATCH_OUTPUT_DIR}"
echo "[run_batch] plots_pdf     : ${PLOTS_PDF}"

if [[ "${failed_count}" -gt 0 ]]; then
  exit 1
fi

exit 0
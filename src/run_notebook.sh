#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTEBOOK_PATH="${1:-${PROJECT_ROOT}/two_rink_reaching_jerk_change.ipynb}"
VENV_PATH="${VENV_PATH:-/Users/rikunishida114/Desktop/rl/SB}"
KERNEL_NAME="${KERNEL_NAME:-SB}"
OUTPUT_NOTEBOOK="${OUTPUT_NOTEBOOK:-${PROJECT_ROOT}/two_rink_reaching_jerk_change.executed.ipynb}"

JUPYTER_DATA_DIR="${JUPYTER_DATA_DIR:-${PROJECT_ROOT}/.jupyter_data}"
export JUPYTER_DATA_DIR

RUN_ID="$(
python - <<'PY'
from datetime import datetime
print(datetime.now().strftime("%Y_%m_%d_%H_%M_%S_%f"))
PY
)"
RUNTIME_DIR="${PROJECT_ROOT}/codex_runtime"
LOG_PATH="${RUNTIME_DIR}/notebook_${RUN_ID}.log"
PID_PATH="${RUNTIME_DIR}/notebook_${RUN_ID}.pid"
META_PATH="${RUNTIME_DIR}/notebook_${RUN_ID}.meta"
JOB_SCRIPT="${RUNTIME_DIR}/notebook_${RUN_ID}_job.sh"

mkdir -p "${RUNTIME_DIR}" "${JUPYTER_DATA_DIR}"

echo "[run_notebook] project root : ${PROJECT_ROOT}"
echo "[run_notebook] notebook     : ${NOTEBOOK_PATH}"
echo "[run_notebook] venv         : ${VENV_PATH}"
echo "[run_notebook] kernel       : ${KERNEL_NAME}"
echo "[run_notebook] jupyter data : ${JUPYTER_DATA_DIR}"

if [[ ! -f "${NOTEBOOK_PATH}" ]]; then
  echo "[run_notebook] notebook not found: ${NOTEBOOK_PATH}" >&2
  exit 1
fi

if [[ ! -d "${VENV_PATH}" ]]; then
  echo "[run_notebook] venv not found: ${VENV_PATH}" >&2
  exit 1
fi

if [[ ! -f "${VENV_PATH}/bin/activate" ]]; then
  echo "[run_notebook] activate script not found: ${VENV_PATH}/bin/activate" >&2
  exit 1
fi

if compgen -G "${RUNTIME_DIR}/*.pid" > /dev/null; then
  for pid_file in "${RUNTIME_DIR}"/*.pid; do
    [[ -f "${pid_file}" ]] || continue
    old_pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -n "${old_pid}" ]] && ps -p "${old_pid}" >/dev/null 2>&1; then
      echo "[run_notebook] another notebook job is still running: pid=${old_pid}" >&2
      echo "[run_notebook] stop it first or wait until it finishes." >&2
      exit 1
    fi
  done
fi

# shellcheck disable=SC1090
source "${VENV_PATH}/bin/activate"

echo "[run_notebook] python: $(which python)"

python - <<'PY'
import sys
print("[run_notebook] sys.executable:", sys.executable)

try:
    import stable_baselines3
    print("[run_notebook] stable_baselines3:", stable_baselines3.__file__)
except Exception as e:
    raise SystemExit(f"[run_notebook] import stable_baselines3 failed: {e}")

try:
    import ipykernel
    print("[run_notebook] ipykernel:", ipykernel.__file__)
except Exception as e:
    raise SystemExit(f"[run_notebook] import ipykernel failed: {e}")

try:
    import nbformat
    import nbclient
    print("[run_notebook] nbformat:", nbformat.__file__)
    print("[run_notebook] nbclient:", nbclient.__file__)
except Exception as e:
    raise SystemExit(f"[run_notebook] import nbformat/nbclient failed: {e}")
PY

python - <<PY
import json
import subprocess
import sys

kernel_name = "${KERNEL_NAME}"

out = subprocess.check_output(
    ["jupyter", "kernelspec", "list", "--json"],
    text=True
)
data = json.loads(out)

if kernel_name not in data.get("kernelspecs", {}):
    print(f"[run_notebook] registering kernelspec: {kernel_name}")
    subprocess.check_call([
        sys.executable, "-m", "ipykernel", "install",
        "--user",
        "--name", kernel_name,
        "--display-name", f"Python ({kernel_name})"
    ])
else:
    print(f"[run_notebook] kernelspec already exists: {kernel_name}")
PY

cat > "${JOB_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="${PROJECT_ROOT}"
NOTEBOOK_PATH="${NOTEBOOK_PATH}"
VENV_PATH="${VENV_PATH}"
KERNEL_NAME="${KERNEL_NAME}"
OUTPUT_NOTEBOOK="${OUTPUT_NOTEBOOK}"
LOG_PATH="${LOG_PATH}"
RUN_ID="${RUN_ID}"
JUPYTER_DATA_DIR="${JUPYTER_DATA_DIR}"
export JUPYTER_DATA_DIR

# shellcheck disable=SC1090
source "\${VENV_PATH}/bin/activate"
cd "\${PROJECT_ROOT}"

echo "[job] started_at=\$(date '+%F %T')"
echo "[job] host=\$(hostname)"
echo "[job] pwd=\$(pwd)"
echo "[job] python=\$(which python)"
echo "[job] jupyter_data_dir=\${JUPYTER_DATA_DIR}"

python "\${PROJECT_ROOT}/execute_notebook.py" \
  --notebook "\${NOTEBOOK_PATH}" \
  --kernel "\${KERNEL_NAME}" \
  --output "\${OUTPUT_NOTEBOOK}"

STATUS=\$?
echo "[job] finished_at=\$(date '+%F %T')"
echo "[job] exit_status=\${STATUS}"

LATEST_LOG_DIR=\$(
python - <<'PY'
from pathlib import Path

logs_dir = Path("${PROJECT_ROOT}") / "logs"
if not logs_dir.exists():
    print("")
else:
    dirs = [p for p in logs_dir.iterdir() if p.is_dir()]
    if not dirs:
        print("")
    else:
        latest = max(dirs, key=lambda p: p.stat().st_mtime)
        print(latest)
PY
)

if [[ -n "\${LATEST_LOG_DIR}" && -d "\${LATEST_LOG_DIR}" ]]; then
  cp "\${LOG_PATH}" "\${LATEST_LOG_DIR}/notebook_run.log" 2>/dev/null || true
  {
    echo "run_id=\${RUN_ID}"
    echo "pid=\$\$"
    echo "started_at=\$(date '+%F %T')"
    echo "output_notebook=\${OUTPUT_NOTEBOOK}"
    echo "log_path=\${LOG_PATH}"
    echo "jupyter_data_dir=\${JUPYTER_DATA_DIR}"
    echo "job_exit_status=\${STATUS}"
  } > "\${LATEST_LOG_DIR}/background_job_info.txt"
fi

exit \${STATUS}
EOF

chmod +x "${JOB_SCRIPT}"

nohup bash "${JOB_SCRIPT}" > "${LOG_PATH}" 2>&1 &
JOB_PID=$!

echo "${JOB_PID}" > "${PID_PATH}"

cat > "${META_PATH}" <<EOF
run_id=${RUN_ID}
pid=${JOB_PID}
notebook=${NOTEBOOK_PATH}
output_notebook=${OUTPUT_NOTEBOOK}
venv=${VENV_PATH}
kernel=${KERNEL_NAME}
jupyter_data_dir=${JUPYTER_DATA_DIR}
launched_at=$(date '+%F %T')
log_path=${LOG_PATH}
pid_file=${PID_PATH}
job_script=${JOB_SCRIPT}
status_check=ps -p ${JOB_PID} -o pid=,ppid=,stat=,etime=,command=
tail_log=tail -f ${LOG_PATH}
EOF

sleep 1

if ! ps -p "${JOB_PID}" >/dev/null 2>&1; then
  echo "[run_notebook] background process failed to start." >&2
  echo "[run_notebook] inspect log: ${LOG_PATH}" >&2
  exit 1
fi

echo "[run_notebook] launched background job with nohup."
echo "[run_notebook] pid        : ${JOB_PID}"
echo "[run_notebook] log        : ${LOG_PATH}"
echo "[run_notebook] meta       : ${META_PATH}"
echo
echo "[run_notebook] monitor commands:"
echo "  ps -p ${JOB_PID} -o pid=,ppid=,stat=,etime=,command="
echo "  tail -f ${LOG_PATH}"
echo
echo "[run_notebook] note:"
echo "  notebook execution should continue after terminal disconnect"
echo "  as long as the Mac stays awake and the process is not killed."
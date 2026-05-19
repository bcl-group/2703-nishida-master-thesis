#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd


def find_latest_log_dir(logs_root: Path) -> Path:
    if not logs_root.exists():
        raise FileNotFoundError(f"logs root not found: {logs_root}")
    candidates = [p for p in logs_root.iterdir() if p.is_dir()]
    if not candidates:
        raise FileNotFoundError(f"no log directories found under: {logs_root}")
    return max(candidates, key=lambda p: p.stat().st_mtime)


def find_first_existing_column(df: pd.DataFrame, candidates: list[str]) -> Optional[str]:
    for c in candidates:
        if c in df.columns:
            return c
    return None


def safe_float(value) -> Optional[float]:
    if value is None:
        return None
    if pd.isna(value):
        return None
    try:
        return float(value)
    except Exception:
        return None


def safe_int(value) -> Optional[int]:
    if value is None:
        return None
    if pd.isna(value):
        return None
    try:
        return int(value)
    except Exception:
        return None


def count_local_peaks(y: np.ndarray) -> int:
    if len(y) < 3:
        return 0
    count = 0
    for i in range(1, len(y) - 1):
        if y[i] > y[i - 1] and y[i] >= y[i + 1]:
            count += 1
    return count


def compute_path_length_ratio(x: np.ndarray, y: np.ndarray) -> Optional[float]:
    if len(x) < 2 or len(y) < 2:
        return None
    dx = np.diff(x)
    dy = np.diff(y)
    path_length = float(np.sum(np.sqrt(dx * dx + dy * dy)))
    straight = float(np.sqrt((x[-1] - x[0]) ** 2 + (y[-1] - y[0]) ** 2))
    if straight <= 1.0e-12:
        return None
    return path_length / straight


def fit_gaussian_profile(t: np.ndarray, speed: np.ndarray) -> dict:
    result = {
        "gauss_center_error": None,
        "gauss_rmse": None,
        "gauss_r2": None,
    }

    if len(t) < 5 or len(speed) < 5:
        return result

    duration = float(t[-1] - t[0])
    if duration <= 1.0e-12:
        return result

    t = np.asarray(t, dtype=float)
    speed = np.asarray(speed, dtype=float)

    valid = ~(np.isnan(t) | np.isnan(speed))
    t = t[valid]
    speed = speed[valid]

    if len(t) < 5:
        return result

    tau = (t - t[0]) / duration

    speed = np.clip(speed, 0.0, None)
    vmax = float(np.nanmax(speed))
    if vmax <= 1.0e-12:
        return result
    v_norm = speed / vmax

    w_sum = float(np.sum(v_norm))
    if w_sum <= 1.0e-12:
        return result

    mu = float(np.sum(tau * v_norm) / w_sum)
    var = float(np.sum(v_norm * (tau - mu) ** 2) / w_sum)
    sigma = math.sqrt(max(var, 1.0e-8))

    basis = np.exp(-0.5 * ((tau - mu) / sigma) ** 2)
    denom = float(np.dot(basis, basis))
    if denom <= 1.0e-12:
        return result

    amp = float(np.dot(v_norm, basis) / denom)
    g_fit = amp * basis

    residual = v_norm - g_fit
    rmse = float(np.sqrt(np.mean(residual ** 2)))

    ss_res = float(np.sum(residual ** 2))
    ss_tot = float(np.sum((v_norm - np.mean(v_norm)) ** 2))
    r2 = None if ss_tot <= 1.0e-12 else float(1.0 - ss_res / ss_tot)

    result["gauss_center_error"] = abs(mu - 0.5)
    result["gauss_rmse"] = rmse
    result["gauss_r2"] = r2
    return result


def evaluate_episode_metrics(csv_path: Path) -> dict:
    df = pd.read_csv(csv_path)

    success_col = find_first_existing_column(
        df,
        ["success", "is_success", "Success", "done_success"],
    )
    reward_col = find_first_existing_column(
        df,
        ["total_reward", "episode_reward", "reward_sum", "return", "TotalReward"],
    )

    result = {
        "episode_metrics_csv": str(csv_path),
        "success_rate_all": None,
        "success_rate_100": None,
        "success_rate_1000": None,
        "mean_total_reward_100": None,
        "mean_total_reward_1000": None,
    }

    if success_col is not None:
        success = pd.to_numeric(df[success_col], errors="coerce").fillna(0.0)
        result["success_rate_all"] = safe_float(success.mean())
        result["success_rate_100"] = safe_float(success.tail(100).mean())
        result["success_rate_1000"] = safe_float(success.tail(1000).mean())

    if reward_col is not None:
        rewards = pd.to_numeric(df[reward_col], errors="coerce")
        result["mean_total_reward_100"] = safe_float(rewards.tail(100).mean())
        result["mean_total_reward_1000"] = safe_float(rewards.tail(1000).mean())

    return result


def evaluate_eval_metrics(csv_path: Path) -> dict:
    df = pd.read_csv(csv_path)

    mean_reward_col = find_first_existing_column(
        df,
        ["mean_reward", "eval_mean_reward", "MeanReward"],
    )
    mean_ep_length_col = find_first_existing_column(
        df,
        ["mean_ep_length", "mean_episode_length", "eval_mean_ep_length", "MeanEpLength"],
    )

    result = {
        "eval_metrics_csv": str(csv_path),
        "last_eval_mean_reward": None,
        "last_eval_mean_ep_length": None,
    }

    if mean_reward_col is not None and len(df) > 0:
        result["last_eval_mean_reward"] = safe_float(
            pd.to_numeric(df[mean_reward_col], errors="coerce").iloc[-1]
        )

    if mean_ep_length_col is not None and len(df) > 0:
        result["last_eval_mean_ep_length"] = safe_float(
            pd.to_numeric(df[mean_ep_length_col], errors="coerce").iloc[-1]
        )

    return result


def evaluate_trajectory(csv_path: Path) -> dict:
    df = pd.read_csv(csv_path)

    time_col = find_first_existing_column(df, ["Time", "time", "t"])
    x_col = find_first_existing_column(df, ["HandX", "hand_x", "x", "X"])
    y_col = find_first_existing_column(df, ["HandY", "hand_y", "y", "Y"])
    speed_col = find_first_existing_column(
        df,
        ["HandSpeed (m/s)", "HandSpeed", "hand_speed", "speed"],
    )
    vx_col = find_first_existing_column(df, ["HandVx (m/s)", "HandVx", "hand_vx", "vx"])
    vy_col = find_first_existing_column(df, ["HandVy (m/s)", "HandVy", "hand_vy", "vy"])

    result = {
        "trajectory_csv": str(csv_path),
        "time_col": time_col,
        "x_col": x_col,
        "y_col": y_col,
        "speed_col": speed_col,
        "vx_col": vx_col,
        "vy_col": vy_col,
        "path_length_ratio": None,
        "peak_time_ratio": None,
        "peak_count": None,
        "duration": None,
        "max_speed": None,
        "gauss_center_error": None,
        "gauss_rmse": None,
        "gauss_r2": None,
    }

    if time_col is None or x_col is None or y_col is None:
        return result

    t = pd.to_numeric(df[time_col], errors="coerce").to_numpy()
    x = pd.to_numeric(df[x_col], errors="coerce").to_numpy()
    y = pd.to_numeric(df[y_col], errors="coerce").to_numpy()

    valid_mask = ~(np.isnan(t) | np.isnan(x) | np.isnan(y))
    t = t[valid_mask]
    x = x[valid_mask]
    y = y[valid_mask]

    if len(t) < 2:
        return result

    duration = float(t[-1] - t[0])
    result["duration"] = duration
    result["path_length_ratio"] = compute_path_length_ratio(x, y)

    if speed_col is not None:
        speed = pd.to_numeric(df[speed_col], errors="coerce").to_numpy()
        speed = speed[valid_mask]
    else:
        dt = np.diff(t)
        dx = np.diff(x)
        dy = np.diff(y)
        inst_speed = np.full_like(t, fill_value=np.nan, dtype=float)
        valid_dt = np.abs(dt) > 1.0e-12
        sp = np.full_like(dt, fill_value=np.nan, dtype=float)
        sp[valid_dt] = np.sqrt(dx[valid_dt] ** 2 + dy[valid_dt] ** 2) / dt[valid_dt]
        if len(sp) > 0:
            inst_speed[1:] = sp
            inst_speed[0] = sp[0]
        speed = inst_speed

    good = ~np.isnan(speed)
    speed = speed[good]
    t_speed = t[good]

    if len(speed) > 0:
        result["max_speed"] = safe_float(np.nanmax(speed))
        result["peak_count"] = safe_int(count_local_peaks(speed))

        peak_idx = int(np.nanargmax(speed))
        if duration > 1.0e-12:
            peak_time_ratio = float((t_speed[peak_idx] - t[0]) / duration)
            result["peak_time_ratio"] = peak_time_ratio

        gauss_metrics = fit_gaussian_profile(t_speed, speed)
        result.update(gauss_metrics)

    return result


def write_markdown(summary: dict, output_path: Path) -> None:
    lines = []
    lines.append("# Codex iteration summary")
    lines.append("")
    lines.append("## Core metrics")
    for key in [
        "success_rate_1000",
        "success_rate_100",
        "success_rate_all",
        "peak_count",
        "peak_time_ratio",
        "gauss_center_error",
        "gauss_rmse",
        "gauss_r2",
        "path_length_ratio",
        "mean_total_reward_1000",
        "mean_total_reward_100",
        "last_eval_mean_reward",
        "last_eval_mean_ep_length",
    ]:
        lines.append(f"- {key}: `{summary.get(key)}`")

    lines.append("")
    lines.append("## Files")
    for key in [
        "latest_log_dir",
        "episode_metrics_csv",
        "eval_metrics_csv",
        "trajectory_csv",
    ]:
        lines.append(f"- {key}: `{summary.get(key)}`")

    output_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="final")
    parser.add_argument("--log_dir", default=None)
    args = parser.parse_args()

    project_root = Path.cwd()
    logs_root = project_root / "logs"

    log_dir = Path(args.log_dir).expanduser().resolve() if args.log_dir else find_latest_log_dir(logs_root)

    episode_metrics_csv = log_dir / "episode_full_metrics.csv"
    eval_metrics_csv = log_dir / "eval_metrics.csv"
    trajectory_csv = log_dir / "end_result_2joint_post_env.csv"

    summary: dict = {
        "latest_log_dir": str(log_dir),
    }

    if episode_metrics_csv.exists():
        summary.update(evaluate_episode_metrics(episode_metrics_csv))

    if eval_metrics_csv.exists():
        summary.update(evaluate_eval_metrics(eval_metrics_csv))

    if trajectory_csv.exists():
        summary.update(evaluate_trajectory(trajectory_csv))

    json_path = log_dir / "codex_iteration_summary.json"
    md_path = log_dir / "codex_iteration_summary.md"

    json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    write_markdown(summary, md_path)

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"[evaluate_latest_run] wrote: {json_path}")
    print(f"[evaluate_latest_run] wrote: {md_path}")


if __name__ == "__main__":
    main()
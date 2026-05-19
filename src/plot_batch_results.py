import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def numericize(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    for c in cols:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def plot_single_bar(
    df: pd.DataFrame,
    x_col: str,
    y_col: str,
    title: str,
    ylabel: str,
    out: Path,
    ideal=None,
) -> None:
    if y_col not in df.columns:
        return

    plt.figure(figsize=(9, 5))
    plt.bar(df[x_col], df[y_col])
    if ideal is not None:
        plt.axhline(ideal, linestyle="--", linewidth=1.5)
    plt.title(title)
    plt.xlabel("candidate")
    plt.ylabel(ylabel)
    plt.tight_layout()
    plt.savefig(out, dpi=150)
    plt.close()


def plot_grouped_bar(
    df: pd.DataFrame,
    x_col: str,
    y_cols: list[str],
    title: str,
    ylabel: str,
    out: Path,
) -> None:
    valid_cols = [c for c in y_cols if c in df.columns]
    if not valid_cols:
        return

    plt.figure(figsize=(10, 6))
    x = list(range(len(df)))
    width = 0.8 / len(valid_cols)

    for i, col in enumerate(valid_cols):
        offset = (i - (len(valid_cols) - 1) / 2) * width
        xpos = [v + offset for v in x]
        plt.bar(xpos, df[col], width=width, label=col)

    plt.xticks(x, df[x_col])
    plt.title(title)
    plt.xlabel("candidate")
    plt.ylabel(ylabel)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out, dpi=150)
    plt.close()


def write_index_md(batch_id: str, output_dir: Path) -> None:
    files = [
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

    lines = [f"# Plot index: {batch_id}", ""]
    for f in files:
        p = output_dir / f
        if p.exists():
            lines.append(f"## {f}")
            lines.append(f"![{f}]({f})")
            lines.append("")

    (output_dir / f"{batch_id}_plots.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary_csv", required=True)
    parser.add_argument("--batch_id", required=True)
    parser.add_argument("--output_dir", required=True)
    args = parser.parse_args()

    summary_csv = Path(args.summary_csv)
    output_dir = Path(args.output_dir)
    batch_id = args.batch_id

    ensure_dir(output_dir)

    df = pd.read_csv(summary_csv)
    if "candidate_id" not in df.columns:
        raise ValueError("summary csv must contain candidate_id")

    numeric_cols = [
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
    ]
    df = numericize(df, numeric_cols)

    # 1. success rate
    plot_grouped_bar(
        df,
        "candidate_id",
        ["success_rate_1000", "success_rate_100", "success_rate_all"],
        f"Success Rates ({batch_id})",
        "success rate",
        output_dir / "success_rates.png",
    )

    # 2. peak_count
    plot_single_bar(
        df,
        "candidate_id",
        "peak_count",
        f"Peak Count ({batch_id})",
        "peak_count",
        output_dir / "peak_count.png",
        ideal=1.0,
    )

    # 3. peak_time_ratio
    plot_single_bar(
        df,
        "candidate_id",
        "peak_time_ratio",
        f"Peak Time Ratio ({batch_id})",
        "peak_time_ratio",
        output_dir / "peak_time_ratio.png",
        ideal=0.5,
    )

    # 4. gauss_center_error
    plot_single_bar(
        df,
        "candidate_id",
        "gauss_center_error",
        f"Gaussian Center Error ({batch_id})",
        "gauss_center_error",
        output_dir / "gauss_center_error.png",
        ideal=0.0,
    )

    # 5. gauss_rmse
    plot_single_bar(
        df,
        "candidate_id",
        "gauss_rmse",
        f"Gaussian RMSE ({batch_id})",
        "gauss_rmse",
        output_dir / "gauss_rmse.png",
        ideal=0.0,
    )

    # 6. gauss_r2
    plot_single_bar(
        df,
        "candidate_id",
        "gauss_r2",
        f"Gaussian R2 ({batch_id})",
        "gauss_r2",
        output_dir / "gauss_r2.png",
        ideal=1.0,
    )

    # 7. path_length_ratio
    plot_single_bar(
        df,
        "candidate_id",
        "path_length_ratio",
        f"Path Length Ratio ({batch_id})",
        "path_length_ratio",
        output_dir / "path_length_ratio.png",
        ideal=1.0,
    )

    # 8. reward metrics
    plot_grouped_bar(
        df,
        "candidate_id",
        ["mean_total_reward_1000", "mean_total_reward_100", "last_eval_mean_reward"],
        f"Reward Metrics ({batch_id})",
        "reward",
        output_dir / "reward_metrics.png",
    )

    # 9. eval length
    plot_single_bar(
        df,
        "candidate_id",
        "last_eval_mean_ep_length",
        f"Last Eval Mean Episode Length ({batch_id})",
        "episode length",
        output_dir / "eval_length.png",
    )

    write_index_md(batch_id, output_dir)
    print(f"[plot_batch_results] saved plots to: {output_dir}")


if __name__ == "__main__":
    main()
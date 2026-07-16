#!/usr/bin/env python3
"""
Gas Sensing System — Offline Sensitivity Plotter
=================================================
Loads a CSV log produced by gas_logger.py and generates:
  1. Sensitivity % vs. time
  2. R_gas vs. time (raw ADC code)
  3. ΔR vs. time

Usage:
    python3 plot_sensitivity.py gas_log.csv
    python3 plot_sensitivity.py gas_log.csv --rolling 20  # 20-sample rolling mean
    python3 plot_sensitivity.py gas_log.csv --save plot.png
"""

import argparse
import sys

try:
    import pandas as pd
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates
    from matplotlib.gridspec import GridSpec
except ImportError:
    print("ERROR: Install dependencies: pip install pandas matplotlib")
    sys.exit(1)


def load_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    required = {"timestamp_unix", "r_gas", "r_air", "delta", "sensitivity_x100"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"CSV is missing columns: {missing}")

    df["timestamp"] = pd.to_datetime(df["timestamp_unix"], unit="s", utc=True)
    df["sensitivity_pct"] = df["sensitivity_x100"] / 100.0
    df = df.sort_values("timestamp").reset_index(drop=True)
    return df


def plot(df: pd.DataFrame, rolling: int, save_path: str | None):
    fig = plt.figure(figsize=(14, 8), facecolor="#1a1a2e")
    gs  = GridSpec(3, 1, figure=fig, hspace=0.45)

    ax1 = fig.add_subplot(gs[0])
    ax2 = fig.add_subplot(gs[1], sharex=ax1)
    ax3 = fig.add_subplot(gs[2], sharex=ax1)

    t = df["timestamp"]
    style = dict(linewidth=1.2, alpha=0.8)

    # --- Sensitivity % ---
    sens = df["sensitivity_pct"]
    ax1.plot(t, sens, color="#a78bfa", label="Sensitivity %", **style)
    if rolling > 1:
        ax1.plot(t, sens.rolling(rolling).mean(), color="#f0abfc",
                 linewidth=2.0, label=f"Rolling mean ({rolling})", linestyle="--")
    ax1.axhline(0, color="#ffffff30", linewidth=0.8)
    _style_ax(ax1, "Sensitivity (%)", "#a78bfa")

    # --- R_gas ---
    ax2.plot(t, df["r_gas"], color="#34d399", label="R_gas (ADC code)", **style)
    ax2.plot(t, df["r_air"], color="#f59e0b", label="R_air (baseline)", **style,
             linewidth=0.8, linestyle=":")
    _style_ax(ax2, "ADC Code", "#34d399")
    ax2.legend(loc="upper right", fontsize=8, facecolor="#2d2d4e", edgecolor="none",
               labelcolor="white")

    # --- ΔR ---
    delta = df["delta"]
    ax3.fill_between(t, delta, 0,
                     where=(delta >= 0), color="#34d399", alpha=0.3)
    ax3.fill_between(t, delta, 0,
                     where=(delta < 0),  color="#f87171", alpha=0.3)
    ax3.plot(t, delta, color="#cbd5e1", **style)
    ax3.axhline(0, color="#ffffff50", linewidth=0.8)
    _style_ax(ax3, "ΔR (ADC counts)", "#cbd5e1")

    # X-axis formatting on bottom panel only
    ax3.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
    plt.setp(ax3.xaxis.get_majorticklabels(), rotation=30, ha="right", color="#94a3b8")
    plt.setp(ax1.xaxis.get_majorticklabels(), visible=False)
    plt.setp(ax2.xaxis.get_majorticklabels(), visible=False)

    # Title
    start = df["timestamp"].iloc[0].strftime("%Y-%m-%d %H:%M UTC")
    fig.suptitle(f"Gas Sensor Sensitivity  —  {start}  —  {len(df)} samples",
                 color="white", fontsize=13, y=0.98)

    # Summary stats
    print(f"\nSummary ({len(df)} samples):")
    print(f"  Sensitivity:  min={sens.min():.2f}%  max={sens.max():.2f}%  mean={sens.mean():.2f}%")
    print(f"  R_gas range:  {df['r_gas'].min()}–{df['r_gas'].max()} (ADC codes)")
    print(f"  R_air (baseline): {df['r_air'].iloc[0]}")
    print(f"  ΔR range:     {delta.min()}–{delta.max()}")

    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
        print(f"\nSaved to: {save_path}")
    else:
        plt.show()


def _style_ax(ax, ylabel: str, color: str):
    ax.set_facecolor("#16213e")
    ax.tick_params(colors="#94a3b8", labelsize=8)
    ax.set_ylabel(ylabel, color=color, fontsize=9)
    for spine in ax.spines.values():
        spine.set_edgecolor("#334155")
    ax.yaxis.label.set_color(color)
    ax.grid(True, color="#334155", linewidth=0.5, linestyle="--")


def main():
    parser = argparse.ArgumentParser(description="Gas sensor log plotter")
    parser.add_argument("csv", help="Input CSV file from gas_logger.py")
    parser.add_argument("--rolling", type=int, default=1,
                        help="Rolling mean window size (default: 1 = off)")
    parser.add_argument("--save", default=None, help="Save plot to file instead of showing")
    args = parser.parse_args()

    df = load_csv(args.csv)
    print(f"Loaded {len(df)} rows from {args.csv}")
    plot(df, args.rolling, args.save)


if __name__ == "__main__":
    main()

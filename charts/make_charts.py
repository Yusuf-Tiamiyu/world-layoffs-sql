"""Draw the two README charts from the query results in ../results/.

Run after exporting the TSVs (see README, "Reproduce"):
    python charts/make_charts.py
"""
from pathlib import Path

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RESULTS, OUT = ROOT / "results", ROOT / "charts"

SURFACE, INK, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, BLUE_LIGHT = "#2a78d6", "#9ec5f4"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "font.family": "Segoe UI", "font.size": 10, "text.color": INK,
    "axes.edgecolor": GRID, "axes.labelcolor": MUTED,
    "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.spines.top": False, "axes.spines.right": False, "axes.spines.left": False,
})


def monthly_layoffs():
    df = pd.read_csv(RESULTS / "monthly.tsv", sep="\t")
    df["month"] = pd.to_datetime(df["month"])
    peak = df.loc[df["people_laid_off"].idxmax()]

    fig, ax = plt.subplots(figsize=(9, 3.6), dpi=150)
    colors = [BLUE if m >= pd.Timestamp("2022-09-01") else BLUE_LIGHT for m in df["month"]]
    ax.bar(df["month"], df["people_laid_off"], width=24, color=colors, edgecolor=SURFACE, linewidth=1)
    ax.yaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.yaxis.set_major_formatter(lambda v, _: f"{v / 1000:.0f}k")
    ax.tick_params(length=0)
    ax.xaxis.set_major_locator(mdates.MonthLocator(bymonth=[1, 7]))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
    ax.set_xlim(pd.Timestamp("2020-02-01"), pd.Timestamp("2023-04-15"))

    ax.annotate(f"Jan 2023: {peak['people_laid_off']:,.0f}",
                xy=(peak["month"], peak["people_laid_off"]),
                xytext=(-12, 0), textcoords="offset points", ha="right", va="center", color=INK)
    ax.annotate("Mar 2023: 6 days\nof data only", xy=(df["month"].iloc[-1], df["people_laid_off"].iloc[-1]),
                xytext=(14, 44), textcoords="offset points", ha="left", color=MUTED, fontsize=8.5,
                arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))

    fig.text(0.01, 0.97, "People laid off per month, Mar 2020 to Mar 2023", fontsize=12, weight="bold", va="top")
    fig.text(0.01, 0.89, "The second wave (dark bars, from Sep 2022) was bigger than the 2020 pandemic wave",
             color=MUTED, va="top")
    fig.subplots_adjust(top=0.8, left=0.06, right=0.9, bottom=0.1)
    fig.savefig(OUT / "monthly_layoffs.png")


def shutdown_by_stage():
    df = pd.read_csv(RESULTS / "shutdown_by_stage.tsv", sep="\t")
    order = ["Early (Seed to B)", "Growth (C to D)", "Late private (E+)", "Public"]
    df = df.set_index("funding_stage").loc[order].reset_index()

    fig, ax = plt.subplots(figsize=(7.5, 2.8), dpi=150)
    colors = [BLUE] + [BLUE_LIGHT] * (len(df) - 1)
    ax.barh(df["funding_stage"], df["shutdown_rate_pct"], color=colors, height=0.6)
    ax.invert_yaxis()
    ax.xaxis.set_visible(False)
    ax.tick_params(length=0)
    for y, (rate, n) in enumerate(zip(df["shutdown_rate_pct"], df["n"])):
        ax.text(rate + 0.3, y, f"{rate:.1f}%  (of {n} events)", va="center", color=INK)
    ax.set_xlim(0, df["shutdown_rate_pct"].max() * 1.45)

    fig.text(0.01, 0.97, "Share of layoffs that were full shutdowns, by funding stage", fontsize=12,
             weight="bold", va="top")
    fig.text(0.01, 0.86, "Counted over events that report a percentage; a shutdown is 100% of staff",
             color=MUTED, va="top")
    fig.subplots_adjust(top=0.74, left=0.2, right=0.98, bottom=0.04)
    fig.savefig(OUT / "shutdown_by_stage.png")


if __name__ == "__main__":
    monthly_layoffs()
    shutdown_by_stage()
    print("charts written to", OUT)

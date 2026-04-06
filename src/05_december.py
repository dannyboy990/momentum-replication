"""
05_december.py — December Depletion Falsification

Tax-loss harvesting depletes the loser pool before December's PreTOM window.
This script shows that the Loser-PreTOM effect is approximately zero in December
but strong in non-December months (especially September).

Input:  data/portfolio_daily.parquet (from 02)
Output: output/table_december.csv, output/fig_december.pdf
"""

import os
import sys
import warnings

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import stats

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import DATA_DIR, OUTPUT_DIR, N_DECILES

warnings.filterwarnings("ignore", category=FutureWarning)


def load_data():
    """Load portfolio data and FF factors."""
    port = pd.read_parquet(os.path.join(DATA_DIR, "portfolio_daily.parquet"))
    port["date"] = pd.to_datetime(port["date"])

    # Losers
    losers = port[port["decile"] == 1][["date", "t", "is_pretom", "ret_vw"]].copy()
    losers = losers[losers["date"].dt.year >= 1980]

    # Market-adjust if FF factors available
    ff_path = os.path.join(DATA_DIR, "ff3_daily.parquet")
    if os.path.exists(ff_path):
        ff = pd.read_parquet(ff_path)
        losers = losers.merge(ff[["date", "mktrf"]], on="date", how="left")
        losers["ret_ma"] = losers["ret_vw"] - losers["mktrf"]
    else:
        losers["ret_ma"] = losers["ret_vw"]

    losers["month"] = losers["date"].dt.month
    losers["year"] = losers["date"].dt.year
    losers["ym"] = losers["date"].dt.to_period("M")
    losers["ret_bps"] = losers["ret_ma"] * 10000

    return losers


def monthly_pretom_means(losers):
    """
    Compute mean Loser-PreTOM return by calendar month.
    Uses monthly compounding: compound daily returns within PreTOM per month,
    then test cross-month means.
    """
    print("\n" + "=" * 60)
    print("  LOSER-PRETOM RETURNS BY CALENDAR MONTH")
    print("=" * 60)

    pretom = losers[losers["is_pretom"]].copy()

    # Compound daily returns within PreTOM per month
    pretom["logret"] = np.log1p(pretom["ret_ma"])
    monthly = pretom.groupby(["ym", "month"]).agg(
        cum_logret=("logret", "sum"),
        n_days=("logret", "count"),
    ).reset_index()
    monthly["cum_ret_bps"] = (np.expm1(monthly["cum_logret"])) * 10000

    # Also compute simple daily mean for comparison
    daily_means = pretom.groupby("month")["ret_bps"].agg(["mean", "std", "count"])

    rows = []
    month_names = [
        "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    for m in range(1, 13):
        sub = monthly[monthly["month"] == m]["cum_ret_bps"]
        n = len(sub)
        mean = sub.mean()
        se = sub.std() / np.sqrt(n)
        tstat = mean / se if se > 0 else np.nan

        # Daily mean for reference
        d = daily_means.loc[m] if m in daily_means.index else None
        daily_mean = d["mean"] if d is not None else np.nan

        rows.append({
            "Month": month_names[m],
            "N_months": n,
            "Mean (bps/month)": mean,
            "SE": se,
            "t-stat": tstat,
            "Daily mean (bps)": daily_mean,
        })
        print(f"  {month_names[m]:5s}  mean={mean:7.1f} bps/mo  (t={tstat:5.2f}, n={n})")

    result = pd.DataFrame(rows)

    # Highlight key months
    dec = result[result["Month"] == "Dec"].iloc[0]
    sep = result[result["Month"] == "Sep"].iloc[0]
    print(f"\n  December t-stat:  {dec['t-stat']:.2f}")
    print(f"  September t-stat: {sep['t-stat']:.2f}")

    return result


def plot_december(result):
    """Bar chart of Loser-PreTOM return by calendar month."""
    fig, ax = plt.subplots(figsize=(10, 5))

    months = result["Month"]
    means = result["Mean (bps/month)"]
    ses = result["SE"]

    colors = ["firebrick" if m == "Dec" else
              "darkgreen" if m == "Sep" else
              "steelblue" for m in months]

    bars = ax.bar(range(12), means, yerr=1.96 * ses, capsize=3,
                  color=colors, edgecolor="white", alpha=0.85)

    ax.axhline(0, color="gray", ls="--", lw=0.8)
    ax.set_xticks(range(12))
    ax.set_xticklabels(months, fontsize=10)
    ax.set_ylabel("Mean Loser-Mkt PreTOM return (bps/month)", fontsize=11)
    ax.set_title("December Depletion: Loser-PreTOM Returns by Calendar Month", fontsize=12)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    # Annotate December and September
    dec_idx = 11
    sep_idx = 8
    dec_t = result.iloc[dec_idx]["t-stat"]
    sep_t = result.iloc[sep_idx]["t-stat"]
    ax.annotate(f"t={dec_t:.2f}", (dec_idx, means.iloc[dec_idx]),
                textcoords="offset points", xytext=(0, 12),
                ha="center", fontsize=9, color="firebrick")
    ax.annotate(f"t={sep_t:.2f}", (sep_idx, means.iloc[sep_idx]),
                textcoords="offset points", xytext=(0, -18),
                ha="center", fontsize=9, color="darkgreen")

    path = os.path.join(OUTPUT_DIR, "fig_december.pdf")
    fig.savefig(path, bbox_inches="tight", dpi=150)
    plt.close(fig)
    print(f"\n  Saved: {path}")


def dec_vs_nondec_test(losers):
    """Formal test: December vs non-December PreTOM returns."""
    print("\n" + "=" * 60)
    print("  DECEMBER vs NON-DECEMBER TEST")
    print("=" * 60)

    pretom = losers[losers["is_pretom"]].copy()

    dec = pretom[pretom["month"] == 12]["ret_bps"]
    nondec = pretom[pretom["month"] != 12]["ret_bps"]

    t, p = stats.ttest_ind(dec, nondec, equal_var=False)
    print(f"  December mean:     {dec.mean():.2f} bps/day (n={len(dec)})")
    print(f"  Non-December mean: {nondec.mean():.2f} bps/day (n={len(nondec)})")
    print(f"  Difference:        {dec.mean() - nondec.mean():.2f} bps/day")
    print(f"  t-stat:            {t:.2f}")
    print(f"  p-value:           {p:.3f}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Loading data...")
    losers = load_data()
    print(f"  {len(losers):,} loser-day observations")

    # Month-by-month analysis
    result = monthly_pretom_means(losers)
    result.to_csv(os.path.join(OUTPUT_DIR, "table_december.csv"), index=False)
    print(f"  Saved: {os.path.join(OUTPUT_DIR, 'table_december.csv')}")

    # Figure
    plot_december(result)

    # Formal test
    dec_vs_nondec_test(losers)

    print("\nDone. Proceed to 06_tables_figures.py")


if __name__ == "__main__":
    main()

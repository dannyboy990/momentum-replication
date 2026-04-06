"""
04_did_t1.py — Difference-in-Differences: T+1 Settlement Reform

The SEC moved equity settlement from T+2 to T+1 on May 28, 2024.
Under T+2, funds selling to meet month-end redemptions had to trade by t=-4.
Under T+1, the deadline shifts to t=-3. This script estimates the triple-DiD:
Post x Loser x PreTOM.

Input:  data/stock_panel.parquet (from 02), data/portfolio_daily.parquet
Output: output/table_did_t1.csv, output/fig_selling_migration.pdf
"""

import os
import sys
import warnings

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import statsmodels.api as sm

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import DATA_DIR, OUTPUT_DIR, T1_REFORM_DATE, PRETOM_START, PRETOM_END

warnings.filterwarnings("ignore", category=FutureWarning)


def load_stock_panel():
    """Load stock-level panel from 02_build_portfolios."""
    path = os.path.join(DATA_DIR, "stock_panel.parquet")
    if not os.path.exists(path):
        print("ERROR: stock_panel.parquet not found. Run 02_build_portfolios.py first.")
        sys.exit(1)

    print("Loading stock panel...")
    df = pd.read_parquet(path)
    df["date"] = pd.to_datetime(df["date"])
    print(f"  {len(df):,} stock-day observations")
    return df


def portfolio_level_did():
    """
    Portfolio-level DiD: compare t=-4 vs t=-3 for losers,
    before and after T+1 reform.
    """
    print("\n" + "=" * 60)
    print("  PORTFOLIO-LEVEL DiD: t=-4 vs t=-3")
    print("=" * 60)

    port_path = os.path.join(DATA_DIR, "portfolio_daily.parquet")
    port = pd.read_parquet(port_path)
    port["date"] = pd.to_datetime(port["date"])

    # Loser portfolio (decile 1)
    losers = port[port["decile"] == 1].copy()
    losers = losers[losers["date"].dt.year >= 1980]

    # Market-adjusted returns (need FF factors)
    ff_path = os.path.join(DATA_DIR, "ff3_daily.parquet")
    if os.path.exists(ff_path):
        ff = pd.read_parquet(ff_path)
        losers = losers.merge(ff[["date", "mktrf"]], on="date", how="left")
        losers["ret_ma"] = (losers["ret_vw"] - losers["mktrf"]) * 10000  # bps
    else:
        losers["ret_ma"] = losers["ret_vw"] * 10000

    reform = pd.Timestamp(T1_REFORM_DATE)

    # Keep only t=-4 and t=-3
    edge = losers[losers["t"].isin([-4, -3])].copy()
    edge["post"] = (edge["date"] >= reform).astype(int)
    edge["day_m4"] = (edge["t"] == -4).astype(int)

    # 2x2 cell means
    print("\n  Cell means (mkt-adj loser return, bps):")
    print(f"  {'':20s} {'Pre-T+1':>12s} {'Post-T+1':>12s}")
    for d in [1, 0]:
        label = "T-4" if d == 1 else "T-3"
        pre = edge.loc[(edge["day_m4"] == d) & (edge["post"] == 0), "ret_ma"]
        post = edge.loc[(edge["day_m4"] == d) & (edge["post"] == 1), "ret_ma"]
        print(f"  {label:20s} {pre.mean():12.2f} (n={len(pre):3d})  {post.mean():12.2f} (n={len(post):3d})")

    # DiD regression
    y = edge["ret_ma"]
    X = pd.DataFrame({
        "const": 1,
        "day_m4": edge["day_m4"],
        "post": edge["post"],
        "did": edge["day_m4"] * edge["post"],
    })

    model = sm.OLS(y, X).fit(cov_type="HC1")
    did_coef = model.params["did"]
    did_t = model.tvalues["did"]
    did_p = model.pvalues["did"]

    print(f"\n  DiD (T-4 x Post-T+1): {did_coef:.2f} bps (t={did_t:.2f}, p={did_p:.3f})")

    return model


def stock_level_did(df):
    """
    Stock-level triple-DiD: Post x Loser x PreTOM.
    Uses OLS with demeaned data (approximates stock + month FE).
    """
    print("\n" + "=" * 60)
    print("  STOCK-LEVEL TRIPLE DiD: Post x Loser x PreTOM")
    print("=" * 60)

    reform = pd.Timestamp(T1_REFORM_DATE)

    # Keep D1 (losers) and D10 (winners) only
    df = df[df["decile"].isin([1, 10])].copy()
    df = df[df["date"].dt.year >= 1980]

    df["ret_bps"] = df["ret"] * 10000
    df["post"] = (df["date"] >= reform).astype(int)
    df["loser"] = (df["decile"] == 1).astype(int)
    df["pretom"] = df["is_pretom"].astype(int)

    # Interactions
    df["loser_pretom"] = df["loser"] * df["pretom"]
    df["post_loser"] = df["post"] * df["loser"]
    df["post_pretom"] = df["post"] * df["pretom"]
    df["triple"] = df["post"] * df["loser"] * df["pretom"]

    print(f"  Observations: {len(df):,}")
    print(f"  Stocks: {df['permno'].nunique():,}")
    print(f"  Pre-reform: {(df['post'] == 0).sum():,}")
    print(f"  Post-reform: {(df['post'] == 1).sum():,}")

    # Demean by stock and month (approximate FE via within-transformation)
    df["ym"] = df["date"].dt.to_period("M")

    # Stock FE: demean within stock
    stock_mean = df.groupby("permno")["ret_bps"].transform("mean")
    df["ret_dm"] = df["ret_bps"] - stock_mean

    # Month FE: demean within month (after stock demeaning)
    month_mean = df.groupby("ym")["ret_dm"].transform("mean")
    df["ret_dm2"] = df["ret_dm"] - month_mean

    # Regression variables (also demean)
    xvars = ["loser", "pretom", "post", "loser_pretom", "post_loser",
             "post_pretom", "triple"]
    for v in xvars:
        sm_v = df.groupby("permno")[v].transform("mean")
        mm_v = df.groupby("ym")[v].transform("mean")
        df[v + "_dm"] = df[v] - sm_v - mm_v + df[v].mean()

    y = df["ret_dm2"]
    X = sm.add_constant(df[[v + "_dm" for v in xvars]])
    X.columns = ["const"] + xvars

    print("  Running OLS (this may take a moment for large samples)...")
    model = sm.OLS(y, X).fit(cov_type="HC1")

    print(f"\n  Triple DiD (Post x Loser x PreTOM):")
    print(f"    Coefficient: {model.params['triple']:.2f} bps")
    print(f"    t-stat:      {model.tvalues['triple']:.2f}")
    print(f"    p-value:     {model.pvalues['triple']:.3f}")

    print(f"\n  Loser x PreTOM (baseline, full sample):")
    print(f"    Coefficient: {model.params['loser_pretom']:.2f} bps")
    print(f"    t-stat:      {model.tvalues['loser_pretom']:.2f}")

    # Save results
    results = pd.DataFrame({
        "Variable": model.params.index,
        "Coefficient": model.params.values,
        "Std Error": model.bse.values,
        "t-stat": model.tvalues.values,
        "p-value": model.pvalues.values,
    })
    results.to_csv(os.path.join(OUTPUT_DIR, "table_did_t1.csv"), index=False)
    print(f"\n  Saved: {os.path.join(OUTPUT_DIR, 'table_did_t1.csv')}")

    return model


def plot_selling_migration(df):
    """
    Plot average loser return by trading day, pre vs post T+1 reform.
    Shows migration of the selling trough from t=-4 to t=-3.
    """
    print("\nGenerating selling migration figure...")

    reform = pd.Timestamp(T1_REFORM_DATE)

    losers = df[df["decile"] == 1].copy()
    losers = losers[losers["date"].dt.year >= 2020]  # focus on recent period
    losers["ret_bps"] = losers["ret"] * 10000
    losers["post"] = (losers["date"] >= reform).astype(int)

    # Keep t in [-9, 0] for readability
    losers = losers[losers["t"].between(-9, 0)]

    # Mean by t and pre/post
    means = losers.groupby(["t", "post"])["ret_bps"].agg(["mean", "sem"]).reset_index()

    fig, ax = plt.subplots(figsize=(10, 5))

    for post_val, label, color, marker in [
        (0, f"Pre-T+1 (2020 to May 2024)", "steelblue", "o"),
        (1, f"Post-T+1 (June 2024+)", "firebrick", "s"),
    ]:
        sub = means[means["post"] == post_val]
        ax.errorbar(sub["t"], sub["mean"], yerr=1.96 * sub["sem"],
                     label=label, color=color, marker=marker, capsize=3, lw=1.5)

    # Shade PreTOM window
    ax.axvspan(PRETOM_START, PRETOM_END, alpha=0.1, color="gray",
               label="PreTOM [t-9, t-4]")
    ax.axhline(0, color="gray", ls="--", lw=0.8)
    ax.axvline(-4.5, color="red", ls=":", lw=0.8, alpha=0.5, label="Old deadline (T+2)")
    ax.axvline(-3.5, color="orange", ls=":", lw=0.8, alpha=0.5, label="New deadline (T+1)")

    ax.set_xlabel("Trading day relative to month-end", fontsize=11)
    ax.set_ylabel("Mean loser return (bps)", fontsize=11)
    ax.set_title("Loser Returns by Trading Day: Pre vs Post T+1 Reform", fontsize=12)
    ax.legend(fontsize=9, loc="lower left")
    ax.set_xticks(range(-9, 1))
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    path = os.path.join(OUTPUT_DIR, "fig_selling_migration.pdf")
    fig.savefig(path, bbox_inches="tight", dpi=150)
    plt.close(fig)
    print(f"  Saved: {path}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Portfolio-level DiD (quick, uses portfolio data)
    portfolio_level_did()

    # Stock-level DiD
    df = load_stock_panel()
    stock_level_did(df)

    # Visual: selling migration
    plot_selling_migration(df)

    print("\nDone. Proceed to 05_december.py")


if __name__ == "__main__":
    main()

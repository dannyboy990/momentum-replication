"""
02_build_portfolios.py — Momentum Portfolios and PreTOM Split

Constructs momentum decile portfolios with NYSE breakpoints,
computes daily VW/EW returns, and tags PreTOM vs Complementary days.

Input:  data/crsp_daily.parquet, data/crsp_monthly.parquet
Output: data/portfolio_daily.parquet, output/momentum_daily.csv
"""

import os
import sys
import time

import pandas as pd
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import (
    DATA_DIR, OUTPUT_DIR,
    FORMATION_MONTHS, SKIP_MONTHS, N_DECILES,
    PRETOM_START, PRETOM_END,
)


def compute_momentum_signal(df_monthly):
    """
    Compute cumulative return over [t-12, t-2] for each stock-month.
    Standard Jegadeesh-Titman (1993) formation: 12-month lookback, skip 1 month.
    """
    print("Computing momentum signals...")
    df = df_monthly.copy()
    df = df.sort_values(["permno", "date"])

    # Year-month for grouping
    df["ym"] = df["date"].dt.to_period("M")

    # Log returns for compounding
    df["logret"] = np.log1p(df["ret"])

    # Cumulative return over [t-12, t-2]: sum of log returns from 12 months ago
    # through 2 months ago (skip most recent month)
    df["cum_ret"] = (
        df.groupby("permno")["logret"]
        .rolling(window=FORMATION_MONTHS - SKIP_MONTHS, min_periods=FORMATION_MONTHS - SKIP_MONTHS)
        .sum()
        .reset_index(level=0, drop=True)
    )

    # Shift by SKIP_MONTHS to skip the most recent month
    df["mom_signal"] = df.groupby("permno")["cum_ret"].shift(SKIP_MONTHS)

    # Convert back from log
    df["mom_signal"] = np.expm1(df["mom_signal"])

    n_valid = df["mom_signal"].notna().sum()
    print(f"  {n_valid:,} stock-months with valid momentum signal")
    return df


def assign_deciles_nyse(df):
    """
    Assign momentum deciles using NYSE breakpoints.
    Only NYSE stocks (exchcd==1) determine the breakpoints;
    all stocks are then assigned to deciles.
    """
    print("Assigning deciles (NYSE breakpoints)...")

    df = df.dropna(subset=["mom_signal"])

    def _assign_month(g):
        nyse = g[g["exchcd"] == 1]["mom_signal"]
        if len(nyse) < N_DECILES:
            g["decile"] = np.nan
            return g
        breakpoints = np.percentile(
            nyse, np.linspace(0, 100, N_DECILES + 1)[1:-1]
        )
        g["decile"] = np.searchsorted(breakpoints, g["mom_signal"], side="right") + 1
        return g

    df = df.groupby("ym", group_keys=False).apply(_assign_month)
    df["decile"] = df["decile"].astype("Int8")
    df = df.dropna(subset=["decile"])

    print(f"  {len(df):,} stock-months with decile assignments")
    print(f"  Decile counts (sample month):")
    sample = df[df["ym"] == df["ym"].max()]
    print(sample.groupby("decile")["permno"].count().to_string(header=False))
    return df


def build_trading_day_calendar(dates):
    """
    For each trading day, compute t = position relative to month-end.
    t=0 is the last trading day of the month, t=-1 is second-to-last, etc.
    """
    print("Building trading day calendar...")
    cal = pd.DataFrame({"date": sorted(dates.unique())})
    cal["ym"] = cal["date"].dt.to_period("M")

    # Within each month, rank from end: last day = 0, second-to-last = -1, etc.
    cal["t"] = cal.groupby("ym").cumcount(ascending=False)
    cal["t"] = -cal["t"]  # negate so last day = 0

    # Also compute days from month start (for positive t convention)
    cal["t_from_start"] = cal.groupby("ym").cumcount()

    # Number of trading days per month
    cal["n_days"] = cal.groupby("ym")["date"].transform("count")

    # PreTOM flag
    cal["is_pretom"] = (cal["t"] >= PRETOM_START) & (cal["t"] <= PRETOM_END)

    print(f"  {len(cal):,} trading days")
    print(f"  PreTOM days: {cal['is_pretom'].sum():,} ({cal['is_pretom'].mean():.1%})")
    print(f"  Trading days per month: {cal['n_days'].median():.0f} median")
    return cal


def compute_portfolio_returns(df_monthly, df_daily, cal):
    """
    Apply monthly decile assignments to daily returns.
    Value-weight within each decile using lagged market cap.
    """
    print("Computing daily portfolio returns...")
    t0 = time.time()

    # Merge monthly decile assignments onto daily data
    # Each month's assignment applies to the NEXT month's daily returns
    assignments = df_monthly[["permno", "ym", "decile", "me"]].copy()
    assignments = assignments.rename(columns={"me": "me_lag"})

    # Shift: assignment from month m applies to daily returns in month m+1
    assignments["holding_ym"] = assignments["ym"] + 1

    df_daily = df_daily.copy()
    df_daily["ym"] = df_daily["date"].dt.to_period("M")

    # Merge
    panel = df_daily.merge(
        assignments[["permno", "holding_ym", "decile", "me_lag"]],
        left_on=["permno", "ym"],
        right_on=["permno", "holding_ym"],
        how="inner",
    )

    # Merge calendar
    panel = panel.merge(cal[["date", "t", "is_pretom"]], on="date", how="left")

    print(f"  Panel: {len(panel):,} stock-day observations")

    # Value-weighted returns within decile-day
    panel = panel.dropna(subset=["ret", "me_lag"])
    panel["me_lag"] = panel["me_lag"].clip(lower=0)

    # Compute weights
    wsum = panel.groupby(["date", "decile"])["me_lag"].transform("sum")
    panel["w"] = panel["me_lag"] / wsum

    # Weighted return
    panel["wret"] = panel["w"] * panel["ret"]

    # Collapse to decile-day
    port = panel.groupby(["date", "decile"]).agg(
        ret_vw=("wret", "sum"),
        ret_ew=("ret", "mean"),
        n_stocks=("permno", "count"),
    ).reset_index()

    # Merge calendar info
    port = port.merge(cal[["date", "t", "is_pretom"]], on="date", how="left")
    port["ym"] = port["date"].dt.to_period("M")

    elapsed = time.time() - t0
    print(f"  Collapsed to {len(port):,} decile-day observations ({elapsed:.0f}s)")

    return port, panel


def build_wml_series(port):
    """
    Build Winner-Minus-Loser daily return series.
    Winners = decile 10, Losers = decile 1.
    """
    print("Building WML series...")

    winners = port[port["decile"] == N_DECILES][["date", "ret_vw", "ret_ew"]].rename(
        columns={"ret_vw": "ret_winner_vw", "ret_ew": "ret_winner_ew"}
    )
    losers = port[port["decile"] == 1][["date", "ret_vw", "ret_ew"]].rename(
        columns={"ret_vw": "ret_loser_vw", "ret_ew": "ret_loser_ew"}
    )

    wml = winners.merge(losers, on="date")
    wml["ret_wml_vw"] = wml["ret_winner_vw"] - wml["ret_loser_vw"]
    wml["ret_wml_ew"] = wml["ret_winner_ew"] - wml["ret_loser_ew"]

    # Merge calendar
    cal_cols = port[["date", "t", "is_pretom", "ym"]].drop_duplicates(subset=["date"])
    wml = wml.merge(cal_cols, on="date")

    # Decompose into PreTOM and Complementary
    wml["wml_pretom"] = np.where(wml["is_pretom"], wml["ret_wml_vw"], 0.0)
    wml["wml_comp"] = np.where(~wml["is_pretom"], wml["ret_wml_vw"], 0.0)
    wml["loser_pretom"] = np.where(wml["is_pretom"], wml["ret_loser_vw"], 0.0)
    wml["winner_pretom"] = np.where(wml["is_pretom"], wml["ret_winner_vw"], 0.0)

    wml = wml.sort_values("date").reset_index(drop=True)
    print(f"  WML series: {len(wml):,} trading days")
    return wml


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    daily_path = os.path.join(DATA_DIR, "crsp_daily.parquet")
    monthly_path = os.path.join(DATA_DIR, "crsp_monthly.parquet")

    if not os.path.exists(daily_path) or not os.path.exists(monthly_path):
        print("ERROR: Data files not found. Run 01_pull_crsp.py first.")
        sys.exit(1)

    print("Loading data...")
    df_daily = pd.read_parquet(daily_path)
    df_monthly = pd.read_parquet(monthly_path)
    print(f"  Daily: {len(df_daily):,} rows")
    print(f"  Monthly: {len(df_monthly):,} rows")

    # Step 1: Momentum signal
    df_monthly = compute_momentum_signal(df_monthly)

    # Step 2: Decile assignment (NYSE breakpoints)
    df_monthly = assign_deciles_nyse(df_monthly)

    # Step 3: Trading day calendar
    cal = build_trading_day_calendar(df_daily["date"])

    # Step 4: Daily portfolio returns
    port, panel = compute_portfolio_returns(df_monthly, df_daily, cal)

    # Step 5: WML series
    wml = build_wml_series(port)

    # Save portfolio-level data
    port_path = os.path.join(DATA_DIR, "portfolio_daily.parquet")
    port.to_parquet(port_path, index=False)
    print(f"\nSaved: {port_path}")

    # Save WML series as CSV (safe to share, portfolio-level)
    csv_path = os.path.join(OUTPUT_DIR, "momentum_daily.csv")
    wml_out = wml[[
        "date", "t", "is_pretom", "ym",
        "ret_winner_vw", "ret_loser_vw", "ret_wml_vw",
        "ret_winner_ew", "ret_loser_ew", "ret_wml_ew",
        "wml_pretom", "wml_comp",
    ]].copy()
    wml_out["ym"] = wml_out["ym"].astype(str)
    wml_out.to_csv(csv_path, index=False, float_format="%.8f")
    print(f"Saved: {csv_path} ({len(wml_out):,} rows)")

    # Save stock-level panel for DiD (needed by 04_did_t1.py)
    panel_path = os.path.join(DATA_DIR, "stock_panel.parquet")
    panel_cols = ["permno", "date", "ret", "decile", "me_lag", "t", "is_pretom", "ym"]
    panel[panel_cols].to_parquet(panel_path, index=False)
    print(f"Saved: {panel_path} ({len(panel):,} rows)")

    # Quick sanity check
    print("\n" + "=" * 60)
    print("  SANITY CHECK")
    print("=" * 60)
    wml80 = wml[wml["date"] >= "1980-01-01"]
    cum_full = np.expm1(np.log1p(wml80["ret_wml_vw"]).sum())
    cum_pre = np.expm1(np.log1p(wml80["wml_pretom"]).sum())
    cum_comp = np.expm1(np.log1p(wml80["wml_comp"]).sum())
    print(f"  Full WML cumulative (1980+):  ${1 + cum_full:.2f}")
    print(f"  PreTOM cumulative:            ${1 + cum_pre:.2f}")
    print(f"  Complementary cumulative:     ${1 + cum_comp:.2f}")
    print(f"  Trading days: {len(wml80):,}")
    print(f"  PreTOM days:  {wml80['is_pretom'].sum():,} ({wml80['is_pretom'].mean():.1%})")

    mean_loser_pre = wml80.loc[wml80["is_pretom"], "ret_loser_vw"].mean() * 10000
    mean_loser_rest = wml80.loc[~wml80["is_pretom"], "ret_loser_vw"].mean() * 10000
    print(f"  Loser mean (PreTOM):  {mean_loser_pre:.2f} bps/day")
    print(f"  Loser mean (rest):    {mean_loser_rest:.2f} bps/day")

    print("\nDone. Proceed to 03_performance.py")


if __name__ == "__main__":
    main()

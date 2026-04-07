"""
02_build_panel.py — Build Analysis Panel from CRSP Pull

Constructs the stock-level panel and portfolio-level dataset from the
raw CRSP data pulled in 01_pull_crsp.py. Follows the exact procedure
described in Internet Appendix Section IA.1.

This script produces the same files that 00_replicate.do Steps 1-2 expect:
  - data/momentum_daily.dta        (portfolio-level, used by figures + settlement)
  - data/panel_fixed_vw_reg.csv    (stock-level VW, used by _tables_vw.do)
  - data/panel_fixed_bas_reg.csv   (stock-level BAS subset)
  - data/panel_fixed_ew_reg.csv    (stock-level EW)
  - data/taq_panel_2003_2022.csv   (TAQ subset — EMPTY, requires separate WRDS TAQ pull)

After running this script, run 00_replicate.do in Stata.

Input:  data/crsp_daily.parquet, data/crsp_monthly.parquet (from 01)
Output: Files listed above
"""

import os
import sys
import time

import pandas as pd
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import DATA_DIR, OUTPUT_DIR


def build_trading_day_index(dates):
    """
    Step 4 from IA.1: month-relative trading-day index.
    Last trading day = t=0, second-to-last = t=-1, etc.
    """
    cal = pd.DataFrame({"date": sorted(dates)})
    cal["ym"] = cal["date"].dt.to_period("M")
    cal["t"] = cal.groupby("ym").cumcount(ascending=False)
    cal["t"] = -cal["t"]
    return cal


def expand_panel(df, trading_dates):
    """
    Step 3 from IA.1: expand each security's panel so all trading days
    between first and last observed date are present.
    """
    print("  Expanding trading-day panel...")
    t0 = time.time()

    bounds = df.groupby("permno")["date"].agg(["min", "max"]).reset_index()
    bounds.columns = ["permno", "first", "last"]

    all_dates = pd.DataFrame({"date": sorted(trading_dates)})

    expanded = bounds.merge(all_dates, how="cross")
    expanded = expanded[
        (expanded["date"] >= expanded["first"]) &
        (expanded["date"] <= expanded["last"])
    ][["permno", "date"]]

    panel = expanded.merge(df, on=["permno", "date"], how="left")
    panel["is_gap"] = panel["ret"].isna()

    elapsed = time.time() - t0
    print(f"    {len(df):,} -> {len(panel):,} (+{len(panel)-len(df):,} gap rows, {elapsed:.0f}s)")
    return panel


def compute_momentum(panel):
    """
    Steps 5-6 from IA.1: 12-2 momentum from daily returns.
    Invalid if any day in formation window has gap or bad DlyRetMissFlg.
    """
    print("  Computing momentum from daily returns...")
    t0 = time.time()

    panel = panel.copy()
    panel["ym"] = panel["date"].dt.to_period("M")
    panel["logret"] = np.log1p(panel["ret"]).fillna(0)

    # Invalid day flag
    bad_flags = {"MV", "NS", "NT", "RA", "GP", "MP", "DG", "DM", "DP"}
    panel["invalid"] = panel["is_gap"]
    if "retmissflg" in panel.columns:
        panel["invalid"] = panel["invalid"] | (
            panel["retmissflg"].fillna("").str.strip().isin(bad_flags)
        )

    # Monthly: compound returns, track validity
    monthly = panel.groupby(["permno", "ym"]).agg(
        month_logret=("logret", "sum"),
        has_invalid=("invalid", "any"),
    ).reset_index()
    monthly["valid"] = ~monthly["has_invalid"]
    monthly = monthly.sort_values(["permno", "ym"])

    # Rolling 11-month window (t-12 to t-2)
    monthly["cum_lr"] = (
        monthly.groupby("permno")["month_logret"]
        .rolling(11, min_periods=11).sum()
        .reset_index(level=0, drop=True)
    )
    monthly["all_valid"] = (
        monthly.groupby("permno")["valid"]
        .rolling(11, min_periods=11).min()
        .reset_index(level=0, drop=True)
    ).astype(bool)

    # Shift by 1 (skip most recent month)
    monthly["mom"] = monthly.groupby("permno")["cum_lr"].shift(1)
    monthly["mom_valid"] = monthly.groupby("permno")["all_valid"].shift(1)

    monthly["mom"] = np.expm1(monthly["mom"])
    monthly.loc[~monthly["mom_valid"].fillna(False), "mom"] = np.nan

    n = monthly["mom"].notna().sum()
    elapsed = time.time() - t0
    print(f"    {n:,} valid stock-months ({elapsed:.0f}s)")
    return monthly[["permno", "ym", "mom"]]


def fetch_french_breakpoints():
    """Download French NYSE 2-12 prior return breakpoints."""
    import io, zipfile, urllib.request

    bp_path = os.path.join(DATA_DIR, "french_mom_breakpoints.parquet")
    if os.path.exists(bp_path):
        return pd.read_parquet(bp_path)

    print("  Downloading French momentum breakpoints...")
    url = ("https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/"
           "ftp/Prior_2-12_Breakpoints_CSV.zip")
    resp = urllib.request.urlopen(url)
    z = zipfile.ZipFile(io.BytesIO(resp.read()))
    raw = z.read(z.namelist()[0]).decode("utf-8")

    rows = []
    for line in raw.split("\n"):
        line = line.strip()
        if not line or not line[0].isdigit():
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 22:
            continue
        rows.append(parts)

    cols = ["yyyymm", "count"] + [f"p{p}" for p in range(5, 101, 5)]
    bp = pd.DataFrame(rows, columns=cols)
    bp["ym"] = pd.to_datetime(bp["yyyymm"].astype(int).astype(str), format="%Y%m").dt.to_period("M")

    decile_cols = [f"p{p}" for p in range(10, 91, 10)]
    for c in decile_cols:
        bp[c] = pd.to_numeric(bp[c], errors="coerce") / 100.0

    bp[["ym"] + decile_cols].to_parquet(bp_path, index=False)
    return bp[["ym"] + decile_cols]


def assign_deciles(monthly_mom):
    """Step 7: assign deciles using French NYSE breakpoints."""
    print("  Assigning deciles (French NYSE breakpoints)...")

    bp = fetch_french_breakpoints()
    dcols = [f"p{p}" for p in range(10, 91, 10)]

    df = monthly_mom.copy()
    df["bp_ym"] = df["ym"] - 1  # breakpoints from preceding month

    df = df.merge(bp[["ym"] + dcols], left_on="bp_ym", right_on="ym",
                  how="left", suffixes=("", "_bp"))

    bp_vals = df[dcols].values
    signals = df["mom"].values
    deciles = np.full(len(df), np.nan)
    valid = ~np.isnan(signals) & ~np.any(np.isnan(bp_vals), axis=1)

    for i in np.where(valid)[0]:
        deciles[i] = min(np.searchsorted(bp_vals[i], signals[i], side="right") + 1, 10)

    df["decile"] = deciles.astype("Int8")
    n = df["decile"].notna().sum()
    print(f"    {n:,} stock-months with decile assignments")
    return df[["permno", "ym", "decile"]]


def fetch_ff_factors():
    """Download daily Fama-French factors."""
    import io, zipfile, urllib.request

    ff_path = os.path.join(DATA_DIR, "ff3_daily.parquet")
    if os.path.exists(ff_path):
        return pd.read_parquet(ff_path)

    print("  Downloading Fama-French daily factors...")
    url = ("https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/"
           "ftp/F-F_Research_Data_Factors_daily_CSV.zip")
    resp = urllib.request.urlopen(url)
    z = zipfile.ZipFile(io.BytesIO(resp.read()))
    raw = z.read(z.namelist()[0]).decode("utf-8")

    rows = []
    for line in raw.split("\n"):
        line = line.strip()
        if not line or not line[0].isdigit():
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 5:
            continue
        rows.append(parts[:5])

    ff = pd.DataFrame(rows, columns=["date", "mktrf", "smb", "hml", "rf"])
    ff["date"] = pd.to_datetime(ff["date"], format="%Y%m%d")
    for c in ["mktrf", "smb", "hml", "rf"]:
        ff[c] = pd.to_numeric(ff[c], errors="coerce") / 100.0

    ff.to_parquet(ff_path, index=False)
    return ff


def build_portfolio_daily(daily, decile_map, cal, ff):
    """
    Build portfolio-level daily dataset (momentum_daily.dta equivalent).
    VW returns for D1 (losers) and D10 (winners) using daily lagged market cap.
    """
    print("  Building portfolio-level daily data...")

    df = daily.copy()
    df["ym"] = df["date"].dt.to_period("M")

    # Merge deciles
    df = df.merge(decile_map, on=["permno", "ym"], how="inner")
    df = df[df["date"] >= "1980-01-01"]
    df = df.dropna(subset=["ret", "prevcap"])
    df = df[df["prevcap"] > 0]

    # VW returns per decile-day
    wsum = df.groupby(["date", "decile"])["prevcap"].transform("sum")
    df["w"] = df["prevcap"] / wsum
    df["wret"] = df["w"] * df["ret"]

    port = df.groupby(["date", "decile"]).agg(
        ret_vw=("wret", "sum"),
        ret_ew=("ret", "mean"),
    ).reset_index()

    # Pivot to wide: one row per date
    winners = port[port["decile"] == 10][["date", "ret_vw", "ret_ew"]].rename(
        columns={"ret_vw": "winners_vw", "ret_ew": "winners_ew"})
    losers = port[port["decile"] == 1][["date", "ret_vw", "ret_ew"]].rename(
        columns={"ret_vw": "losers_vw", "ret_ew": "losers_ew"})

    wml = winners.merge(losers, on="date")
    wml["wml_vw"] = wml["winners_vw"] - wml["losers_vw"]
    wml["wml_ew"] = wml["winners_ew"] - wml["losers_ew"]

    # Merge calendar and factors
    wml = wml.merge(cal, on="date", how="left")
    wml = wml.merge(ff, on="date", how="left")

    wml = wml.sort_values("date").reset_index(drop=True)
    print(f"    {len(wml):,} trading days")
    return wml


def build_stock_csvs(daily, decile_map, cal, ff):
    """
    Build stock-level CSV files matching what 00_replicate.do Step 2 produces.
    These are the exact inputs for _tables_vw.do, _table2_bas_contemp.do, etc.
    """
    print("  Building stock-level CSVs...")
    t0 = time.time()

    df = daily.copy()
    df["ym"] = df["date"].dt.to_period("M")

    # Merge deciles
    df = df.merge(decile_map, on=["permno", "ym"], how="inner")

    # Merge calendar
    df = df.merge(cal, on="date", how="left")

    # Merge FF factors
    df = df.merge(ff[["date", "rf", "mktrf"]], on="date", how="left")

    # Keep 1980+
    df = df[df["date"] >= "1980-01-01"]

    # Require non-missing return and lagged market cap
    df = df.dropna(subset=["ret", "prevcap"])
    df = df[df["prevcap"] > 0]

    print(f"    Panel: {len(df):,} obs on {df['permno'].nunique():,} securities")

    # Derived variables matching the parquet column names
    df["PERMNO"] = df["permno"]
    df["loser"] = (df["decile"] == 1).astype(int)
    df["preTOM"] = ((df["t"] >= -9) & (df["t"] <= -4)).astype(int)
    df["ret_rf"] = df["ret"] - df["rf"].fillna(0)

    # VW weights: within (date, decile), lagged mcap
    wsum = df.groupby(["date", "decile"])["prevcap"].transform("sum")
    df["w"] = df["prevcap"] / wsum

    # Lagged weight: use previous day's weight (approximate with same-day for now)
    # The paper uses w_l1 = lagged market cap weight. Since we compute weights
    # from prevcap (which IS the lagged cap), w and w_l1 are equivalent here.
    df["w_l1"] = df["w"]

    # BAS
    if "bid" in df.columns and "ask" in df.columns:
        df["bas"] = (df["ask"] - df["bid"]) / ((df["ask"] + df["bid"]) / 2)
        df.loc[(df["ask"] < df["bid"]) | (df["bid"] <= 0), "bas"] = np.nan
    else:
        df["bas"] = np.nan

    # ── panel_fixed_vw_reg.csv ──
    vw_cols = ["date", "PERMNO", "decile", "ret_rf", "t", "loser", "preTOM", "w", "w_l1"]
    vw_path = os.path.join(DATA_DIR, "panel_fixed_vw_reg.csv")
    df[vw_cols].to_csv(vw_path, index=False)
    print(f"    Saved: panel_fixed_vw_reg.csv ({len(df):,} rows)")

    # ── panel_fixed_ew_reg.csv ──
    ew_cols = ["date", "PERMNO", "decile", "ret_rf", "t", "loser", "preTOM", "bas"]
    ew_path = os.path.join(DATA_DIR, "panel_fixed_ew_reg.csv")
    df[ew_cols].to_csv(ew_path, index=False)
    print(f"    Saved: panel_fixed_ew_reg.csv ({len(df):,} rows)")

    # ── panel_fixed_bas_reg.csv ──
    bas_sub = df[df["bas"].notna()]
    bas_cols = ["date", "PERMNO", "decile", "ret_rf", "t", "loser", "preTOM", "w", "w_l1", "bas"]
    bas_path = os.path.join(DATA_DIR, "panel_fixed_bas_reg.csv")
    bas_sub[bas_cols].to_csv(bas_path, index=False)
    print(f"    Saved: panel_fixed_bas_reg.csv ({len(bas_sub):,} rows)")

    # ── taq_panel_2003_2022.csv ──
    # TAQ data requires a separate WRDS pull (WRDS Intraday Indicators).
    # Create an empty placeholder with correct columns so Stata doesn't crash.
    taq_cols = ["permno", "return", "rf", "t", "decile", "loser", "pretom",
                "market_cap_l1", "price", "shares_outstanding",
                "nsp", "sell_share", "inst_share",
                "inst_nsp_within", "inst_nsp_total", "date_str"]
    taq_path = os.path.join(DATA_DIR, "taq_panel_2003_2022.csv")
    pd.DataFrame(columns=taq_cols).to_csv(taq_path, index=False)
    print(f"    Saved: taq_panel_2003_2022.csv (EMPTY — requires separate TAQ pull)")

    elapsed = time.time() - t0
    print(f"    ({elapsed:.0f}s)")


def save_as_dta(wml_df, path):
    """Save portfolio daily data as Stata .dta file."""
    out = wml_df[[
        "date", "ym", "t",
        "winners_vw", "losers_vw", "wml_vw",
        "winners_ew", "losers_ew", "wml_ew",
        "mktrf", "smb", "hml", "rf",
    ]].copy()

    # Convert types for Stata
    out["date"] = pd.to_datetime(out["date"])
    out["ym"] = out["ym"].astype(str)

    # Stata needs numeric ym — convert to months since 1960
    out["ym_num"] = (pd.to_datetime(out["ym"]).dt.year - 1960) * 12 + pd.to_datetime(out["ym"]).dt.month - 1
    out = out.drop(columns=["ym"]).rename(columns={"ym_num": "ym"})

    out.to_stata(path, write_index=False,
                 convert_dates={"date": "td"},
                 version=118)
    print(f"    Saved: {path} ({len(out):,} obs)")


def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    daily_path = os.path.join(DATA_DIR, "crsp_daily.parquet")
    monthly_path = os.path.join(DATA_DIR, "crsp_monthly.parquet")

    if not os.path.exists(daily_path) or not os.path.exists(monthly_path):
        print("ERROR: Data files not found. Run 01_pull_crsp.py first.")
        sys.exit(1)

    print("Loading CRSP data...")
    daily = pd.read_parquet(daily_path)
    monthly = pd.read_parquet(monthly_path)
    daily["date"] = pd.to_datetime(daily["date"])
    monthly["date"] = pd.to_datetime(monthly["date"])
    print(f"  Daily: {len(daily):,}  Monthly: {len(monthly):,}")

    # Trading day calendar
    trading_dates = sorted(daily["date"].unique())
    cal = build_trading_day_index(trading_dates)

    # Panel expansion
    panel = expand_panel(daily, trading_dates)

    # Momentum signals
    mom = compute_momentum(panel)

    # Decile assignment
    decile_map = assign_deciles(mom)

    # Fama-French factors
    ff = fetch_ff_factors()

    # Portfolio-level daily data → .dta
    print("\nBuilding outputs...")
    wml = build_portfolio_daily(daily, decile_map, cal, ff)
    dta_path = os.path.join(DATA_DIR, "momentum_daily.dta")
    save_as_dta(wml, dta_path)

    # Stock-level CSVs
    build_stock_csvs(daily, decile_map, cal, ff)

    # Sanity check
    print("\n" + "=" * 60)
    print("  SANITY CHECK")
    print("=" * 60)
    cum_full = np.exp(np.log1p(wml["wml_vw"]).sum())
    wml["is_pretom"] = (wml["t"] >= -9) & (wml["t"] <= -4)
    cum_pre = np.exp(np.log1p(np.where(wml["is_pretom"], wml["wml_vw"], 0)).sum())
    cum_comp = np.exp(np.log1p(np.where(~wml["is_pretom"], wml["wml_vw"], 0)).sum())
    print(f"  Full WML:         ${cum_full:.2f}  (target: $45.89)")
    print(f"  PreTOM:           ${cum_pre:.2f}  (target: $18.11)")
    print(f"  Complementary:    ${cum_comp:.2f}  (target: $2.53)")
    print(f"  Trading days:     {len(wml):,}")

    loser_pre = wml.loc[wml["is_pretom"], "losers_vw"]
    mkt_pre = wml.loc[wml["is_pretom"], "mktrf"]
    loser_ma = (loser_pre - mkt_pre) * 10000
    print(f"  Loser-Mkt PreTOM: {loser_ma.mean():.1f} bps/day (t={loser_ma.mean()/(loser_ma.std()/np.sqrt(len(loser_ma))):.2f})")

    print("\nDone. Now run 00_replicate.do in Stata.")
    print(f'  Stata command: do "code/stata/00_replicate.do"')


if __name__ == "__main__":
    main()

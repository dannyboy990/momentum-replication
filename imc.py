"""
imc.py - Single-file Python pipeline for "The Intramonth Momentum Cycle".

Nathan, Suominen, and Tasa (2026).

This file consolidates every Python step the replication needs into one
script with subcommands. The Stata master (code/stata/00_replicate.do)
calls into here; users can also run pieces directly.

Subcommands
-----------
  build      Build data/momentum_daily.dta from the CRSP parquet.
             Replaces _build_momentum_daily.py.
  tc         Transaction-cost decomposition (Internet Appendix Table 2).
             Replaces _transaction_costs_decomp.py.
  holding    Holding-period decomposition (Internet Appendix Table 1).
             Replaces _jt_holding_mktadj_nw.py.
  headline   Three-line cumulative-wealth figure (no WRDS / Stata required).
             Replaces run_imc.py.
  all        Run build -> tc -> holding -> headline in order.

Usage
-----
  python imc.py <subcommand> [--root PATH]

  --root defaults to the directory containing this file. Data files are
  read from <root>/data/ and outputs go to <root>/output/.

Data dependencies
-----------------
  build:    data/crsp_1927-2025_fixed_sorting_full.parquet
  tc:       data/panel_full_march4v7.parquet
  holding:  data/crsp_1927-2025_fixed_sorting_full.parquet
  headline: data/momentum_daily.dta  (produced by `build`)
"""

from __future__ import annotations

import argparse
import os
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

warnings.filterwarnings("ignore")

PRETOM_START, PRETOM_END = -9, -4
SAMPLE_START_YEAR = 1980


# =============================================================================
#  Shared helpers
# =============================================================================

def newey_west_se(x, max_lag: int) -> float:
    """Newey-West HAC standard error for the mean of x."""
    x = np.asarray(x, dtype=float)
    x = x[~np.isnan(x)]
    n = len(x)
    if n < 2:
        return float("nan")
    e = x - x.mean()
    var = (e @ e) / n
    for lag in range(1, max_lag + 1):
        w = 1.0 - lag / (max_lag + 1.0)
        var += 2.0 * w * (e[lag:] @ e[:-lag]) / n
    return float(np.sqrt(var / n))


def newey_west_tstat(x, lags: int = 5):
    """Mean and Newey-West t-stat for x."""
    x = np.asarray(x, dtype=float)
    x = x[~np.isnan(x)]
    if len(x) == 0:
        return float("nan"), float("nan")
    mu = float(x.mean())
    se = newey_west_se(x, lags)
    return mu, mu / se if se and not np.isnan(se) else float("nan")


def stars(t: float) -> str:
    a = abs(t)
    if a > 2.58:
        return "***"
    if a > 1.96:
        return "**"
    if a > 1.65:
        return "*"
    return ""


# =============================================================================
#  build: momentum_daily.dta
# =============================================================================

def cmd_build(root: Path) -> None:
    parquet_path = root / "data" / "crsp_fixed_sorting_panel.parquet"
    output_path = root / "data" / "momentum_daily.dta"

    print(f"[build] Reading parquet: {parquet_path}")
    cols = ["date", "decile", "return", "RF", "Mkt", "SMB", "HML", "t", "w_l1"]
    df = pq.read_table(parquet_path, columns=cols).to_pandas()
    df["date"] = pd.to_datetime(df["date"])
    print(f"  Loaded {len(df):,} rows, {df['date'].nunique():,} unique dates")

    df["ret_rf"] = df["return"] - df["RF"]

    # VW: lagged-mcap weights within decile-date
    for dec, label in [(1, "losers"), (10, "winners")]:
        sub = df[df["decile"] == dec].copy()
        sub["w_norm"] = sub.groupby("date")["w_l1"].transform(lambda x: x / x.sum())
        sub["wr"] = sub["w_norm"] * sub["ret_rf"]
        agg = sub.groupby("date")["wr"].sum().rename(f"{label}_vw")
        df = df.merge(agg, on="date", how="left")

    # EW
    for dec, label in [(1, "losers"), (10, "winners")]:
        sub = df[df["decile"] == dec].copy()
        agg = sub.groupby("date")["ret_rf"].mean().rename(f"{label}_ew")
        df = df.merge(agg, on="date", how="left")

    daily = df.groupby("date").agg(
        t=("t", "first"),
        losers_vw=("losers_vw", "first"),
        winners_vw=("winners_vw", "first"),
        losers_ew=("losers_ew", "first"),
        winners_ew=("winners_ew", "first"),
        mktrf=("Mkt", "first"),
        smb=("SMB", "first"),
        hml=("HML", "first"),
        rf=("RF", "first"),
    ).reset_index()

    daily["wml_vw"] = daily["winners_vw"] - daily["losers_vw"]
    daily["wml_ew"] = daily["winners_ew"] - daily["losers_ew"]

    daily["ym"] = daily["date"].dt.to_period("M").apply(
        lambda x: (x.year - 1960) * 12 + x.month - 1
    )

    if daily["smb"].abs().mean() > 0.5:
        daily["smb"] = daily["smb"] / 100
        daily["hml"] = daily["hml"] / 100

    daily = daily[[
        "date", "ym", "t", "winners_vw", "losers_vw", "wml_vw",
        "winners_ew", "losers_ew", "wml_ew", "mktrf", "smb", "hml", "rf",
    ]]
    daily = daily.sort_values("date").reset_index(drop=True)

    print(f"  Output: {len(daily):,} obs, "
          f"{daily['date'].min().date()} to {daily['date'].max().date()}")
    print(f"  t range: {daily['t'].min()} to {daily['t'].max()}")
    print(f"  1980+ obs: {len(daily[daily['date'].dt.year >= 1980]):,}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    daily.to_stata(
        output_path,
        write_index=False,
        convert_dates={"date": "td"},
        variable_labels={
            "date": "Trading date",
            "ym": "Year-month (Stata monthly)",
            "t": "Trading day relative to month-end (0=last day)",
            "winners_vw": "Winner decile excess return (VW)",
            "losers_vw": "Loser decile excess return (VW)",
            "wml_vw": "WML = Winners - Losers (VW)",
            "winners_ew": "Winner decile excess return (EW)",
            "losers_ew": "Loser decile excess return (EW)",
            "wml_ew": "WML = Winners - Losers (EW)",
            "mktrf": "Market excess return",
            "smb": "SMB factor",
            "hml": "HML factor",
            "rf": "Risk-free rate",
        },
    )
    print(f"  Saved: {output_path}")


# =============================================================================
#  tc: Transaction-cost decomposition (IA Table 2)
# =============================================================================

def cmd_tc(root: Path) -> None:
    parquet_path = root / "data" / "crsp_fixed_sorting_panel.parquet"

    print(f"[tc] Loading parquet: {parquet_path}")
    cols = ["date", "PERMNO", "decile", "return", "market_cap_l1", "bas", "t"]
    pf = pq.read_table(parquet_path, columns=cols).to_pandas()
    pf = pf[pf["date"].dt.year >= 1980].copy()
    pf = pf.dropna(subset=["decile", "market_cap_l1", "return"])
    pf["ym"] = pf["date"].dt.to_period("M")
    pf["year"] = pf["date"].dt.year

    # trade indicator: stock changed decile or new this month
    mem = pf.groupby(["PERMNO", "ym"])["decile"].first().reset_index()
    mem = mem.sort_values(["PERMNO", "ym"])
    mem["dec_lag"] = mem.groupby("PERMNO")["decile"].shift(1)
    mem["ym_lag"] = mem.groupby("PERMNO")["ym"].shift(1)
    mem["trade"] = ((mem["decile"] != mem["dec_lag"]) | mem["dec_lag"].isna()).astype(int)
    ym_ord = mem["ym"].apply(lambda x: x.ordinal)
    ym_lag_ord = mem["ym_lag"].apply(lambda x: x.ordinal if pd.notna(x) else -999)
    mem.loc[(ym_ord - ym_lag_ord) != 1, "trade"] = 1
    pf = pf.merge(mem[["PERMNO", "ym", "trade"]], on=["PERMNO", "ym"], how="left")

    # monthly average quoted spread per stock
    bas_valid = pf[pf["bas"].notna() & (pf["bas"] > 0)]
    bas_mo = bas_valid.groupby(["PERMNO", "ym"])["bas"].mean().reset_index()
    bas_mo.columns = ["PERMNO", "ym", "bas_mo"]
    pf = pf.merge(bas_mo, on=["PERMNO", "ym"], how="left")

    pf["pretom"] = ((pf["t"] >= PRETOM_START) & (pf["t"] <= PRETOM_END)).astype(int)
    print(f"  Obs: {len(pf):,}")

    def decompose(pf_sub: pd.DataFrame) -> pd.DataFrame:
        dat = pf_sub.copy()
        pieces = []
        for dec, dl in [(1, "loser"), (10, "winner")]:
            dsub = dat[dat["decile"] == dec].copy()

            for window_label, window_val in [("pretom", 1), ("rest", 0)]:
                wsub = dsub[dsub["pretom"] == window_val]
                daily = wsub.groupby(["ym", "date"]).apply(
                    lambda x: np.average(x["return"], weights=x["market_cap_l1"]),
                    include_groups=False,
                ).reset_index(name="ret")
                daily["ret_1p"] = 1 + daily["ret"]
                mret = daily.groupby("ym")["ret_1p"].prod().reset_index()
                mret.columns = ["ym", f"{dl}_{window_label}_1p"]
                mret[f"{dl}_{window_label}_bps"] = (mret[f"{dl}_{window_label}_1p"] - 1) * 10000
                pieces.append(mret[["ym", f"{dl}_{window_label}_bps"]])

            daily_full = dsub.groupby(["ym", "date"]).apply(
                lambda x: np.average(x["return"], weights=x["market_cap_l1"]),
                include_groups=False,
            ).reset_index(name="ret")
            daily_full["ret_1p"] = 1 + daily_full["ret"]
            mret_full = daily_full.groupby("ym")["ret_1p"].prod().reset_index()
            mret_full.columns = ["ym", f"{dl}_full_1p"]
            mret_full[f"{dl}_full_bps"] = (mret_full[f"{dl}_full_1p"] - 1) * 10000
            pieces.append(mret_full[["ym", f"{dl}_full_bps"]])

            first = dsub.groupby(["PERMNO", "ym"]).first().reset_index()
            first = first[first["bas_mo"].notna()]
            first["tc_stock"] = first["bas_mo"] * first["trade"]
            mtc = first.groupby("ym").apply(
                lambda g: np.average(g["tc_stock"], weights=g["market_cap_l1"]) * 10000,
                include_groups=False,
            ).reset_index(name=f"{dl}_tc")
            pieces.append(mtc)

        result = pieces[0]
        for p in pieces[1:]:
            result = result.merge(p, on="ym", how="outer")

        result["wml_pretom"] = result["winner_pretom_bps"] - result["loser_pretom_bps"]
        result["wml_rest"] = result["winner_rest_bps"] - result["loser_rest_bps"]
        result["wml_full"] = result["winner_full_bps"] - result["loser_full_bps"]
        result["tc"] = result["loser_tc"] + result["winner_tc"]
        result["wml_net"] = result["wml_full"] - result["tc"]
        return result

    for label, yr_min, yr_max in [
        ("FULL SAMPLE (1980-2025)", 1980, 2025),
        ("POST-DECIMALIZATION (2001-2025)", 2001, 2025),
    ]:
        print(f"\n{'=' * 70}\n{label}\n{'=' * 70}")
        m = decompose(pf[(pf["year"] >= yr_min) & (pf["year"] <= yr_max)])
        n = len(m)
        g_full = m["wml_full"].mean()
        g_pretom = m["wml_pretom"].mean()
        g_rest = m["wml_rest"].mean()
        tc = m["tc"].mean()
        net = m["wml_net"].mean()
        gs = m["wml_full"].std()
        ns = m["wml_net"].std()
        gt = g_full / (gs / np.sqrt(n))
        nt = net / (ns / np.sqrt(n))
        pt = g_pretom / (m["wml_pretom"].std() / np.sqrt(n))
        rt = g_rest / (m["wml_rest"].std() / np.sqrt(n))
        pct_pretom = g_pretom / g_full * 100 if g_full != 0 else float("nan")

        print(f"\n  n = {n} months")
        print(f"  Gross WML (full month): {g_full:+.1f} bps/mo (t={gt:.2f})")
        print(f"    PreTOM:               {g_pretom:+.1f} bps/mo (t={pt:.2f})  [{pct_pretom:.0f}%]")
        print(f"    Rest:                 {g_rest:+.1f} bps/mo (t={rt:.2f})  [{100 - pct_pretom:.0f}%]")
        print(f"  TC (round-trip BAS):    {tc:.1f} bps/mo")
        print(f"  Net WML:                {net:+.1f} bps/mo (t={nt:.2f})")
        print(f"  Sharpe (ann.): gross={g_full / gs * np.sqrt(12):.2f}, "
              f"net={net / ns * np.sqrt(12):.2f}")


# =============================================================================
#  holding: Holding-period decomposition (IA Table 1)
# =============================================================================

def cmd_holding(root: Path) -> None:
    parquet_path = root / "data" / "crsp_fixed_sorting_panel.parquet"

    print(f"[holding] Loading parquet: {parquet_path}")
    cols = ["date", "PERMNO", "decile", "return", "market_cap_l1", "t", "preTOM", "Mkt", "RF"]
    df = pq.read_table(parquet_path, columns=cols).to_pandas()
    df["date"] = pd.to_datetime(df["date"])
    df["ym"] = df["date"].dt.to_period("M")
    df = df[df["date"] >= "1980-01-01"].copy()
    df = df.dropna(subset=["decile", "return", "market_cap_l1"])
    df = df[df["market_cap_l1"] > 0]
    print(f"  {len(df):,} rows")

    decile_lookup = df.groupby(["PERMNO", "ym"])["decile"].first().reset_index()
    all_ym = sorted(df["ym"].unique())
    ym_to_idx = {ym: i for i, ym in enumerate(all_ym)}
    idx_to_ym = {i: ym for ym, i in ym_to_idx.items()}
    decile_lookup["ym_idx"] = decile_lookup["ym"].map(ym_to_idx)

    date_info = df.groupby("date")[["t", "preTOM", "Mkt", "RF"]].first()
    date_info["mkt_raw"] = date_info["Mkt"] + date_info["RF"]

    daily = df[["date", "PERMNO", "ym", "return", "market_cap_l1"]].copy()
    MAX_K = 12

    def vw_returns_for_vintage(daily_data, lag_months):
        lookup = decile_lookup[["PERMNO", "ym_idx", "decile"]].copy()
        lookup["ym_idx"] = lookup["ym_idx"] + lag_months
        lookup = lookup[lookup["ym_idx"].isin(idx_to_ym)]
        lookup["ym"] = lookup["ym_idx"].map(idx_to_ym)
        lookup = lookup[["PERMNO", "ym", "decile"]]
        merged = daily_data.merge(lookup, on=["PERMNO", "ym"], how="inner")

        def vw(grp):
            w = grp["market_cap_l1"].values
            r = grp["return"].values
            tw = w.sum()
            return np.dot(w, r) / tw if tw > 0 else np.nan

        w_ret = merged[merged["decile"] == 10].groupby("date").apply(vw)
        l_ret = merged[merged["decile"] == 1].groupby("date").apply(vw)
        return pd.DataFrame({"winner": w_ret, "loser": l_ret})

    print("  Computing VW returns by vintage...")
    vintage_rets = {}
    for j in range(MAX_K):
        print(f"    vintage {j}...", end="", flush=True)
        vintage_rets[j] = vw_returns_for_vintage(daily, j)
        print(" done")

    K_values = [1, 3, 6, 9, 12]
    results = []
    for K in K_values:
        nw_lags = max(K - 1, 0)
        w_frames = [vintage_rets[j]["winner"].rename(f"w{j}") for j in range(K)]
        l_frames = [vintage_rets[j]["loser"].rename(f"l{j}") for j in range(K)]
        port = pd.DataFrame({
            "winner": pd.concat(w_frames, axis=1).mean(axis=1),
            "loser": pd.concat(l_frames, axis=1).mean(axis=1),
        })
        port = port.join(date_info)
        port["wml"] = port["winner"] - port["loser"]
        port["winner_mktadj"] = port["winner"] - port["mkt_raw"]
        port["loser_mktadj"] = port["loser"] - port["mkt_raw"]

        valid = port.dropna(subset=["wml", "preTOM", "mkt_raw"]).copy()
        valid["ym"] = valid.index.to_period("M")

        for series_name, col in [
            ("Loser-Mkt", "loser_mktadj"),
            ("Winner-Mkt", "winner_mktadj"),
            ("WML", "wml"),
        ]:
            pretom_m = valid[valid["preTOM"] == 1].groupby("ym")[col].apply(
                lambda x: (1 + x).prod() - 1)
            rest_m = valid[valid["preTOM"] == 0].groupby("ym")[col].apply(
                lambda x: (1 + x).prod() - 1)
            total_m = valid.groupby("ym")[col].apply(
                lambda x: (1 + x).prod() - 1)

            pm = pretom_m.mean() * 10000
            rm = rest_m.mean() * 10000
            tm = total_m.mean() * 10000

            pse_nw = newey_west_se(pretom_m * 10000, nw_lags)
            rse_nw = newey_west_se(rest_m * 10000, nw_lags)
            tse_nw = newey_west_se(total_m * 10000, nw_lags)

            pse = pretom_m.std() / np.sqrt(len(pretom_m)) * 10000
            rse = rest_m.std() / np.sqrt(len(rest_m)) * 10000
            tse = total_m.std() / np.sqrt(len(total_m)) * 10000

            results.append({
                "K": K, "series": series_name, "nw_lags": nw_lags,
                "pretom_bps": pm, "rest_bps": rm, "total_bps": tm,
                "pretom_t_nw": pm / pse_nw if pse_nw > 0 else 0,
                "rest_t_nw": rm / rse_nw if rse_nw > 0 else 0,
                "total_t_nw": tm / tse_nw if tse_nw > 0 else 0,
                "pretom_t_plain": pm / pse if pse > 0 else 0,
                "rest_t_plain": rm / rse if rse > 0 else 0,
                "total_t_plain": tm / tse if tse > 0 else 0,
                "wealth_pretom": (1 + pretom_m).prod(),
                "wealth_rest": (1 + rest_m).prod(),
            })

    print(f"\n{'=' * 90}")
    print("MARKET-ADJUSTED DECOMPOSITION BY HOLDING PERIOD")
    print("French 12-2 deciles, VW, 1980-2025. Newey-West(K-1) t-stats.")
    print("=" * 90)

    for series in ["Loser-Mkt", "Winner-Mkt", "WML"]:
        print(f"\n  {series}")
        print(f"  {'K':>3} {'NW':>4} {'PreTOM':>9} {'(t)':>8} {'Rest':>9} "
              f"{'(t)':>8} {'Total':>9} {'(t)':>8} {'$Pre':>8} {'$Rest':>8}")
        print("  " + "-" * 80)
        for K in K_values:
            r = next(x for x in results if x["K"] == K and x["series"] == series)
            print(f"  {K:>3} {r['nw_lags']:>4} "
                  f"{r['pretom_bps']:>8.1f}{stars(r['pretom_t_nw'])} ({r['pretom_t_nw']:>5.2f})  "
                  f"{r['rest_bps']:>8.1f}{stars(r['rest_t_nw'])} ({r['rest_t_nw']:>5.2f})  "
                  f"{r['total_bps']:>8.1f}{stars(r['total_t_nw'])} ({r['total_t_nw']:>5.2f})  "
                  f"${r['wealth_pretom']:>6.2f} ${r['wealth_rest']:>6.2f}")

    print(f"\n{'=' * 90}\nt-STAT COMPARISON: Plain vs Newey-West(K-1)\n{'=' * 90}")
    for series in ["Loser-Mkt", "Winner-Mkt", "WML"]:
        print(f"\n  {series}")
        print(f"  {'K':>3} {'NW':>4} | {'PreTOM':>8} {'t_plain':>8} {'t_NW':>8} | "
              f"{'Rest':>8} {'t_plain':>8} {'t_NW':>8} | "
              f"{'Total':>8} {'t_plain':>8} {'t_NW':>8}")
        print("  " + "-" * 90)
        for K in K_values:
            r = next(x for x in results if x["K"] == K and x["series"] == series)
            print(f"  {K:>3} {r['nw_lags']:>4} | "
                  f"{r['pretom_bps']:>8.1f} {r['pretom_t_plain']:>7.2f} "
                  f"{r['pretom_t_nw']:>7.2f}{stars(r['pretom_t_nw'])} | "
                  f"{r['rest_bps']:>8.1f} {r['rest_t_plain']:>7.2f} "
                  f"{r['rest_t_nw']:>7.2f}{stars(r['rest_t_nw'])} | "
                  f"{r['total_bps']:>8.1f} {r['total_t_plain']:>7.2f} "
                  f"{r['total_t_nw']:>7.2f}{stars(r['total_t_nw'])}")


# =============================================================================
#  headline: 3-line cumulative-wealth figure
# =============================================================================

def cmd_headline(root: Path) -> None:
    import matplotlib.pyplot as plt

    data_file = root / "data" / "momentum_daily.dta"
    out_dir = root / "output"

    if not data_file.exists():
        sys.exit(
            f"ERROR: {data_file} not found.\n"
            "Run `python imc.py build` first, or download the prebuilt file."
        )

    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_stata(data_file)
    df = df[df["date"].dt.year >= SAMPLE_START_YEAR].copy()
    df = df.sort_values("date").reset_index(drop=True)

    df["pretom"] = ((df["t"] >= PRETOM_START) & (df["t"] <= PRETOM_END)).astype(int)
    df["wml_pretom"] = np.where(df["pretom"] == 1, df["wml_vw"], 0.0)
    df["wml_rest"] = np.where(df["pretom"] == 0, df["wml_vw"], 0.0)

    df["wealth_full"] = np.exp(np.log1p(df["wml_vw"]).cumsum())
    df["wealth_pretom"] = np.exp(np.log1p(df["wml_pretom"]).cumsum())
    df["wealth_rest"] = np.exp(np.log1p(df["wml_rest"]).cumsum())

    end_full = df["wealth_full"].iloc[-1]
    end_pretom = df["wealth_pretom"].iloc[-1]
    end_rest = df["wealth_rest"].iloc[-1]

    pretom_ret = df.loc[df["pretom"] == 1, "wml_vw"].values * 1e4
    rest_ret = df.loc[df["pretom"] == 0, "wml_vw"].values * 1e4
    losers_pretom = df.loc[df["pretom"] == 1, "losers_vw"].values * 1e4
    losers_rest = df.loc[df["pretom"] == 0, "losers_vw"].values * 1e4
    winners_pretom = df.loc[df["pretom"] == 1, "winners_vw"].values * 1e4
    winners_rest = df.loc[df["pretom"] == 0, "winners_vw"].values * 1e4

    mu_wml_p, t_wml_p = newey_west_tstat(pretom_ret)
    mu_wml_r, t_wml_r = newey_west_tstat(rest_ret)
    mu_los_p, t_los_p = newey_west_tstat(losers_pretom)
    mu_los_r, t_los_r = newey_west_tstat(losers_rest)
    mu_win_p, t_win_p = newey_west_tstat(winners_pretom)
    mu_win_r, t_win_r = newey_west_tstat(winners_rest)

    n_days = len(df)
    n_pretom = int(df["pretom"].sum())
    pretom_share = n_pretom / n_days
    pretom_wealth_share = np.log(end_pretom) / np.log(end_full)

    bar = "=" * 72
    print(f"\n{bar}\n  THE INTRAMONTH MOMENTUM CYCLE - HEADLINE RESULT")
    print(f"  Nathan, Suominen, and Tasa (2026)\n{bar}\n")
    print(f"  Sample: {df['date'].min().date()} to {df['date'].max().date()}"
          f"   ({n_days:,} trading days)")
    print(f"  PreTOM window: t in [{PRETOM_START}, {PRETOM_END}]"
          f"   ({n_pretom:,} days, {pretom_share:.1%} of sample)\n")
    print("  Mean daily VW return (bps), Newey-West t-stat (5 lags):")
    print(f"    WML        PreTOM  {mu_wml_p:+7.2f}  (t = {t_wml_p:+5.2f})")
    print(f"    WML        Rest    {mu_wml_r:+7.2f}  (t = {t_wml_r:+5.2f})")
    print(f"    Losers     PreTOM  {mu_los_p:+7.2f}  (t = {t_los_p:+5.2f})")
    print(f"    Losers     Rest    {mu_los_r:+7.2f}  (t = {t_los_r:+5.2f})")
    print(f"    Winners    PreTOM  {mu_win_p:+7.2f}  (t = {t_win_p:+5.2f})")
    print(f"    Winners    Rest    {mu_win_r:+7.2f}  (t = {t_win_r:+5.2f})\n")
    print("  Cumulative value of $1 invested in WML:")
    print(f"    Full momentum strategy        ${end_full:>9,.2f}")
    print(f"    PreTOM days only              ${end_pretom:>9,.2f}")
    print(f"    Rest-of-month days            ${end_rest:>9,.2f}\n")
    print(f"  PreTOM is {pretom_share:.1%} of trading days but generates "
          f"{pretom_wealth_share:.1%} of log wealth.\n{bar}\n")

    monthly = df.groupby("ym").tail(1)

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(monthly["date"], monthly["wealth_pretom"],
            color="black", lw=2.0,
            label=f"PreTOM only [t-9, t-4]: ${end_pretom:,.2f}")
    ax.plot(monthly["date"], monthly["wealth_full"],
            color="0.40", lw=1.5, ls="--",
            label=f"Full WML: ${end_full:,.2f}")
    ax.plot(monthly["date"], monthly["wealth_rest"],
            color="0.65", lw=1.5, ls=":",
            label=f"Rest of month: ${end_rest:,.2f}")
    ax.set_yscale("log")
    ax.axhline(1.0, color="0.85", lw=0.8)
    ax.set_ylabel("Cumulative value of \\$1 invested (log scale)")
    ax.set_xlabel("")
    ax.set_title("The Intramonth Momentum Cycle: where WML profits come from",
                 fontsize=12, loc="left")
    ax.legend(loc="upper left", frameon=True, framealpha=0.95, fontsize=9)
    ax.grid(True, which="major", axis="y", color="0.92", lw=0.5)
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.tight_layout()

    pdf_path = out_dir / "imc_headline.pdf"
    png_path = out_dir / "imc_headline.png"
    csv_path = out_dir / "imc_headline.csv"
    fig.savefig(pdf_path)
    fig.savefig(png_path, dpi=200)
    plt.close(fig)
    monthly[["date", "wealth_full", "wealth_pretom", "wealth_rest"]].to_csv(
        csv_path, index=False)

    print(f"  Saved: {pdf_path}")
    print(f"  Saved: {png_path}")
    print(f"  Saved: {csv_path}\n")


# =============================================================================
#  CLI
# =============================================================================

COMMANDS = {
    "build":    cmd_build,
    "tc":       cmd_tc,
    "holding":  cmd_holding,
    "headline": cmd_headline,
}


def cmd_all(root: Path) -> None:
    for name in ("build", "tc", "holding", "headline"):
        print(f"\n>>> {name}")
        COMMANDS[name](root)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="imc.py",
        description="Intramonth Momentum Cycle - Python pipeline.",
    )
    parser.add_argument(
        "command",
        choices=list(COMMANDS) + ["all"],
        help="subcommand to run",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="replication root (default: directory containing imc.py)",
    )
    args = parser.parse_args()

    if args.command == "all":
        cmd_all(args.root)
    else:
        COMMANDS[args.command](args.root)


if __name__ == "__main__":
    main()

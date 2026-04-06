"""
03_performance.py — Cumulative Wealth and Factor Alphas

Reproduces headline performance statistics: cumulative wealth from $1,
summary statistics, and Fama-French 3-factor alphas.

Input:  data/portfolio_daily.parquet (from 02)
Output: output/table_performance.csv, output/fig_cumulative_wealth.pdf
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
import statsmodels.api as sm

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import DATA_DIR, OUTPUT_DIR, PRETOM_START, PRETOM_END, N_DECILES

warnings.filterwarnings("ignore", category=FutureWarning)


def load_wml():
    """Load portfolio-level daily data from 02_build_portfolios output."""
    port_path = os.path.join(DATA_DIR, "portfolio_daily.parquet")
    if not os.path.exists(port_path):
        print("ERROR: portfolio_daily.parquet not found. Run 02_build_portfolios.py first.")
        sys.exit(1)

    port = pd.read_parquet(port_path)
    port["date"] = pd.to_datetime(port["date"])

    # Build WML from decile 1 and 10
    winners = port[port["decile"] == N_DECILES][["date", "ret_vw"]].rename(
        columns={"ret_vw": "ret_winner"}
    )
    losers = port[port["decile"] == 1][["date", "ret_vw"]].rename(
        columns={"ret_vw": "ret_loser"}
    )
    cal = port[["date", "t", "is_pretom"]].drop_duplicates(subset=["date"])

    wml = winners.merge(losers, on="date").merge(cal, on="date")
    wml["ret_wml"] = wml["ret_winner"] - wml["ret_loser"]
    wml = wml.sort_values("date").reset_index(drop=True)

    # Decompose
    wml["wml_pretom"] = np.where(wml["is_pretom"], wml["ret_wml"], 0.0)
    wml["wml_comp"] = np.where(~wml["is_pretom"], wml["ret_wml"], 0.0)
    wml["loser_pretom"] = np.where(wml["is_pretom"], wml["ret_loser"], 0.0)
    wml["winner_pretom"] = np.where(wml["is_pretom"], wml["ret_winner"], 0.0)

    return wml


def fetch_ff_factors():
    """
    Download Fama-French 3 factors (daily) from Ken French's website.
    Falls back to pandas-datareader, then to direct CSV download.
    """
    ff_path = os.path.join(DATA_DIR, "ff3_daily.parquet")
    if os.path.exists(ff_path):
        print("  Loading cached FF3 factors...")
        return pd.read_parquet(ff_path)

    print("  Downloading Fama-French 3 factors (daily)...")
    try:
        from pandas_datareader.famafrench import get_available_datasets
        import pandas_datareader.data as web

        ff = web.DataReader(
            "F-F_Research_Data_Factors_daily", "famafrench",
            start="1926-01-01", end="2025-12-31"
        )[0]
        ff = ff / 100.0  # convert from percent to decimal
        ff.index = pd.to_datetime(ff.index.to_timestamp())
        ff = ff.reset_index().rename(columns={"Date": "date", "index": "date"})
        if "Date" in ff.columns:
            ff = ff.rename(columns={"Date": "date"})
        ff.columns = [c.strip() for c in ff.columns]
        # Standardize column names
        rename = {}
        for c in ff.columns:
            cl = c.lower().replace("-", "").replace(" ", "")
            if cl == "mktrf":
                rename[c] = "mktrf"
            elif cl == "smb":
                rename[c] = "smb"
            elif cl == "hml":
                rename[c] = "hml"
            elif cl == "rf":
                rename[c] = "rf"
        ff = ff.rename(columns=rename)
        ff["date"] = pd.to_datetime(ff["date"])

    except Exception as e:
        print(f"  pandas-datareader failed ({e}). Trying direct download...")
        url = ("https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/"
               "ftp/F-F_Research_Data_Factors_daily_CSV.zip")
        ff = pd.read_csv(url, skiprows=3, header=0)
        ff.columns = ["date", "mktrf", "smb", "hml", "rf"]
        ff = ff[ff["date"].apply(lambda x: str(x).strip().isdigit())]
        ff["date"] = pd.to_datetime(ff["date"].astype(str).str.strip(), format="%Y%m%d")
        for c in ["mktrf", "smb", "hml", "rf"]:
            ff[c] = pd.to_numeric(ff[c], errors="coerce") / 100.0

    ff = ff[["date", "mktrf", "smb", "hml", "rf"]].dropna()
    ff.to_parquet(ff_path, index=False)
    print(f"  Saved: {ff_path} ({len(ff):,} days)")
    return ff


def cumulative_wealth(wml, start_year=1980):
    """Compute cumulative wealth from $1 invested at start of sample."""
    df = wml[wml["date"].dt.year >= start_year].copy()

    series = {
        "Full WML": df["ret_wml"],
        "PreTOM": df["wml_pretom"],
        "Complementary": df["wml_comp"],
    }

    results = {}
    for name, ret in series.items():
        cum = np.expm1(np.log1p(ret).cumsum())
        terminal = 1 + cum.iloc[-1]
        results[name] = terminal

    return results, df


def summary_statistics(wml, start_year=1980):
    """Compute summary statistics table."""
    df = wml[wml["date"].dt.year >= start_year].copy()

    series_map = {
        "Full WML": df["ret_wml"],
        "PreTOM WML": df.loc[df["is_pretom"], "ret_wml"],
        "Comp WML": df.loc[~df["is_pretom"], "ret_wml"],
        "Loser (PreTOM)": df.loc[df["is_pretom"], "ret_loser"],
        "Winner (PreTOM)": df.loc[df["is_pretom"], "ret_winner"],
        "Loser (all days)": df["ret_loser"],
        "Winner (all days)": df["ret_winner"],
    }

    rows = []
    for name, s in series_map.items():
        s = s.dropna()
        n = len(s)
        mean_ann = s.mean() * 252
        vol_ann = s.std() * np.sqrt(252)
        sharpe = mean_ann / vol_ann if vol_ann > 0 else np.nan
        skew = s.skew()
        kurt = s.kurtosis()

        # t-stat for mean
        tstat = s.mean() / (s.std() / np.sqrt(n))

        # Mean in bps/day
        mean_bps = s.mean() * 10000

        rows.append({
            "Series": name,
            "N_days": n,
            "Mean (bps/day)": mean_bps,
            "t-stat": tstat,
            "Ann. Mean (%)": mean_ann * 100,
            "Ann. Vol (%)": vol_ann * 100,
            "Sharpe": sharpe,
            "Skewness": skew,
            "Kurtosis": kurt,
        })

    return pd.DataFrame(rows)


def ff3_alphas(wml, ff, start_year=1980):
    """Regress return series on FF3 factors, Newey-West SEs."""
    df = wml[wml["date"].dt.year >= start_year].copy()
    df = df.merge(ff, on="date", how="inner")

    series_map = {
        "Full WML": df["ret_wml"],
        "Loser (PreTOM)": df["ret_loser"] * df["is_pretom"],
        "Winner (PreTOM)": df["ret_winner"] * df["is_pretom"],
    }

    rows = []
    for name, y in series_map.items():
        X = sm.add_constant(df[["mktrf", "smb", "hml"]])
        mask = y.notna() & X.notna().all(axis=1) & (y != 0)
        if name == "Full WML":
            mask = y.notna() & X.notna().all(axis=1)

        model = sm.OLS(y[mask], X[mask]).fit(cov_type="HAC", cov_kwds={"maxlags": 6})
        rows.append({
            "Series": name,
            "Alpha (bps/day)": model.params["const"] * 10000,
            "Alpha t-stat": model.tvalues["const"],
            "MktRF": model.params["mktrf"],
            "SMB": model.params["smb"],
            "HML": model.params["hml"],
            "R2": model.rsquared,
            "N": int(model.nobs),
        })

    return pd.DataFrame(rows)


def plot_cumulative_wealth(wml, start_year=1980):
    """Three-line cumulative wealth plot."""
    df = wml[wml["date"].dt.year >= start_year].copy()

    fig, ax = plt.subplots(figsize=(10, 6))

    for col, label, ls, color in [
        ("wml_pretom", "PreTOM [t-9, t-4]", "-", "black"),
        ("ret_wml", "Full WML", "--", "gray"),
        ("wml_comp", "Complementary", ":", "silver"),
    ]:
        cum = np.exp(np.log1p(df[col]).cumsum())
        ax.plot(df["date"].values, cum.values, label=label, ls=ls, color=color, lw=1.5)

    ax.set_yscale("log")
    ax.set_ylabel("Cumulative Wealth ($)", fontsize=11)
    ax.set_xlabel("")
    ax.legend(loc="upper left", fontsize=10)
    ax.set_title("Cumulative Wealth: $1 Invested in 1980", fontsize=12)
    ax.grid(True, alpha=0.3)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    path = os.path.join(OUTPUT_DIR, "fig_cumulative_wealth.pdf")
    fig.savefig(path, bbox_inches="tight", dpi=150)
    plt.close(fig)
    print(f"  Saved: {path}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Loading portfolio data...")

    wml = load_wml()
    print(f"  {len(wml):,} trading days loaded")

    # Fama-French factors
    ff = fetch_ff_factors()

    # Cumulative wealth
    print("\n" + "=" * 60)
    print("  CUMULATIVE WEALTH (1980-2025)")
    print("=" * 60)
    wealth, _ = cumulative_wealth(wml)
    for name, val in wealth.items():
        print(f"  {name:25s}  ${val:.2f}")

    # Summary statistics
    print("\n" + "=" * 60)
    print("  SUMMARY STATISTICS")
    print("=" * 60)
    sumstats = summary_statistics(wml)
    print(sumstats.to_string(index=False, float_format="%.2f"))

    sumstats.to_csv(os.path.join(OUTPUT_DIR, "table_performance.csv"), index=False)
    print(f"  Saved: {os.path.join(OUTPUT_DIR, 'table_performance.csv')}")

    # FF3 alphas
    print("\n" + "=" * 60)
    print("  FAMA-FRENCH 3-FACTOR ALPHAS")
    print("=" * 60)
    alphas = ff3_alphas(wml, ff)
    print(alphas.to_string(index=False, float_format="%.3f"))

    alphas.to_csv(os.path.join(OUTPUT_DIR, "table_alphas.csv"), index=False)

    # Figure
    print("\nGenerating cumulative wealth figure...")
    plot_cumulative_wealth(wml)

    # Key numbers
    print("\n" + "=" * 60)
    print("  KEY NUMBERS TO VERIFY")
    print("=" * 60)
    wml80 = wml[wml["date"].dt.year >= 1980]
    loser_pre = wml80.loc[wml80["is_pretom"], "ret_loser"]
    mean_bps = loser_pre.mean() * 10000
    tstat = loser_pre.mean() / (loser_pre.std() / np.sqrt(len(loser_pre)))
    print(f"  Loser-PreTOM mean:     {mean_bps:.1f} bps/day")
    print(f"  Loser-PreTOM t-stat:   {tstat:.2f}")

    print("\nDone. Proceed to 04_did_t1.py")


if __name__ == "__main__":
    main()

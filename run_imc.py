"""
run_imc.py - One-command reproduction of the Intramonth Momentum Cycle (IMC).

Nathan, Suominen, and Tasa (2026), "The Intramonth Momentum Cycle."

This script reproduces the paper's headline result without requiring WRDS,
Stata, or the full ~3-hour pipeline. It loads the pre-built portfolio-level
dataset (data/momentum_daily.dta) and produces:

  1. Console summary of the IMC numbers (mean WML, t-stats, terminal wealth)
  2. output/imc_headline.pdf — three-line cumulative wealth figure
     (Full momentum / PreTOM-only / Rest-of-month)
  3. output/imc_headline.csv — the underlying daily series

Run from the repo root:

    python run_imc.py

Runtime: ~5 seconds. No external data required.
"""

import os
import sys

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

DATA_FILE = os.path.join("data", "momentum_daily.dta")
OUT_DIR = "output"

# PreTOM = six trading days before month-end, t in [-9, -4]
PRETOM_START, PRETOM_END = -9, -4

# Sample window for the headline figure
SAMPLE_START_YEAR = 1980


def newey_west_tstat(x, lags=5):
    """t-stat for the mean of x with Newey-West HAC standard errors."""
    x = np.asarray(x, dtype=float)
    x = x[~np.isnan(x)]
    n = len(x)
    if n == 0:
        return np.nan, np.nan
    mu = x.mean()
    e = x - mu
    gamma0 = (e @ e) / n
    var = gamma0
    for L in range(1, lags + 1):
        w = 1.0 - L / (lags + 1.0)
        gammaL = (e[L:] @ e[:-L]) / n
        var += 2.0 * w * gammaL
    se = np.sqrt(var / n)
    return mu, mu / se


def cumulative_wealth(returns):
    """$1 grown by a daily return series."""
    return float(np.exp(np.log1p(returns).sum()))


def main():
    if not os.path.exists(DATA_FILE):
        sys.exit(
            f"ERROR: {DATA_FILE} not found.\n"
            "Run `python src/01_pull_crsp.py` then `python src/02_build_panel.py` "
            "to construct it, or download the prebuilt file from the release."
        )

    os.makedirs(OUT_DIR, exist_ok=True)

    df = pd.read_stata(DATA_FILE)
    df = df[df["date"].dt.year >= SAMPLE_START_YEAR].copy()
    df = df.sort_values("date").reset_index(drop=True)

    # PreTOM mask
    df["pretom"] = ((df["t"] >= PRETOM_START) & (df["t"] <= PRETOM_END)).astype(int)

    # Daily series for the three strategies
    df["wml_pretom"] = np.where(df["pretom"] == 1, df["wml_vw"], 0.0)
    df["wml_rest"] = np.where(df["pretom"] == 0, df["wml_vw"], 0.0)

    # Cumulative wealth
    df["wealth_full"] = np.exp(np.log1p(df["wml_vw"]).cumsum())
    df["wealth_pretom"] = np.exp(np.log1p(df["wml_pretom"]).cumsum())
    df["wealth_rest"] = np.exp(np.log1p(df["wml_rest"]).cumsum())

    end_full = df["wealth_full"].iloc[-1]
    end_pretom = df["wealth_pretom"].iloc[-1]
    end_rest = df["wealth_rest"].iloc[-1]

    # Mean returns and Newey-West t-stats (in basis points)
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

    # ──────────────────────────────────────────────────────────────────────
    # Console output
    # ──────────────────────────────────────────────────────────────────────
    bar = "=" * 72
    print()
    print(bar)
    print("  THE INTRAMONTH MOMENTUM CYCLE - HEADLINE RESULT")
    print("  Nathan, Suominen, and Tasa (2026)")
    print(bar)
    print()
    print(f"  Sample: {df['date'].min().date()} to {df['date'].max().date()}"
          f"   ({n_days:,} trading days)")
    print(f"  PreTOM window: t in [{PRETOM_START}, {PRETOM_END}]"
          f"   ({n_pretom:,} days, {pretom_share:.1%} of sample)")
    print()
    print("  Mean daily VW return (bps), Newey-West t-stat (5 lags):")
    print(f"    WML        PreTOM  {mu_wml_p:+7.2f}  (t = {t_wml_p:+5.2f})")
    print(f"    WML        Rest    {mu_wml_r:+7.2f}  (t = {t_wml_r:+5.2f})")
    print(f"    Losers     PreTOM  {mu_los_p:+7.2f}  (t = {t_los_p:+5.2f})")
    print(f"    Losers     Rest    {mu_los_r:+7.2f}  (t = {t_los_r:+5.2f})")
    print(f"    Winners    PreTOM  {mu_win_p:+7.2f}  (t = {t_win_p:+5.2f})")
    print(f"    Winners    Rest    {mu_win_r:+7.2f}  (t = {t_win_r:+5.2f})")
    print()
    print("  Cumulative value of $1 invested in WML:")
    print(f"    Full momentum strategy        ${end_full:>9,.2f}")
    print(f"    PreTOM days only              ${end_pretom:>9,.2f}")
    print(f"    Rest-of-month days            ${end_rest:>9,.2f}")
    print()
    print(f"  PreTOM is {pretom_share:.1%} of trading days but generates "
          f"{pretom_wealth_share:.1%} of log wealth.")
    print(bar)
    print()

    # ──────────────────────────────────────────────────────────────────────
    # Headline figure
    # ──────────────────────────────────────────────────────────────────────
    monthly = df.groupby("ym").tail(1)

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(monthly["date"], monthly["wealth_pretom"],
            color="black", lw=2.0, label=f"PreTOM only [t-9, t-4]: ${end_pretom:,.2f}")
    ax.plot(monthly["date"], monthly["wealth_full"],
            color="0.40", lw=1.5, ls="--", label=f"Full WML: ${end_full:,.2f}")
    ax.plot(monthly["date"], monthly["wealth_rest"],
            color="0.65", lw=1.5, ls=":", label=f"Rest of month: ${end_rest:,.2f}")

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
    pdf_path = os.path.join(OUT_DIR, "imc_headline.pdf")
    png_path = os.path.join(OUT_DIR, "imc_headline.png")
    fig.savefig(pdf_path)
    fig.savefig(png_path, dpi=200)
    plt.close(fig)

    out_csv = os.path.join(OUT_DIR, "imc_headline.csv")
    monthly[["date", "wealth_full", "wealth_pretom", "wealth_rest"]].to_csv(
        out_csv, index=False
    )

    print(f"  Saved: {pdf_path}")
    print(f"  Saved: {png_path}")
    print(f"  Saved: {out_csv}")
    print()


if __name__ == "__main__":
    main()

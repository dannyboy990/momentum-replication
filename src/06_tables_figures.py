"""
06_tables_figures.py — Master Output Script

Regenerates all tables and figures after scripts 01-05 have been run.
Also prints a console summary of key numbers for verification against the paper.

Input:  data/portfolio_daily.parquet, data/stock_panel.parquet,
        data/ff3_daily.parquet
Output: All files in output/
"""

import os
import sys
import warnings

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import DATA_DIR, OUTPUT_DIR

warnings.filterwarnings("ignore", category=FutureWarning)

# Change to repo root so relative paths work
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def check_data():
    """Verify required data files exist."""
    required = [
        os.path.join(DATA_DIR, "portfolio_daily.parquet"),
    ]
    missing = [f for f in required if not os.path.exists(f)]
    if missing:
        print("ERROR: Missing data files. Run scripts 01-02 first:")
        for f in missing:
            print(f"  {f}")
        sys.exit(1)


def run_all():
    """Run each analysis script as a subprocess."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    import subprocess

    print("=" * 70)
    print("  THE INTRAMONTH MOMENTUM CYCLE — REPLICATION OUTPUT")
    print("  Nathan, Suominen, and Tasa (2026)")
    print("=" * 70)

    src_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)))
    for script in ["03_performance.py", "04_did_t1.py", "05_december.py"]:
        print(f"\n\n{'#' * 70}")
        print(f"# {script}")
        print("#" * 70)
        result = subprocess.run(
            [sys.executable, os.path.join(src_dir, script)],
            cwd=os.path.dirname(src_dir),
        )
        if result.returncode != 0:
            print(f"  WARNING: {script} exited with code {result.returncode}")


def print_summary():
    """Print key numbers for verification against the paper."""
    import pandas as pd
    import numpy as np

    port = pd.read_parquet(os.path.join(DATA_DIR, "portfolio_daily.parquet"))
    port["date"] = pd.to_datetime(port["date"])

    winners = port[port["decile"] == 10][["date", "ret_vw", "t", "is_pretom"]]
    losers = port[port["decile"] == 1][["date", "ret_vw"]].rename(
        columns={"ret_vw": "ret_loser"}
    )

    wml = winners.merge(losers, on="date")
    wml = wml.rename(columns={"ret_vw": "ret_winner"})
    wml["ret_wml"] = wml["ret_winner"] - wml["ret_loser"]

    df = wml[wml["date"].dt.year >= 1980].copy()

    # Cumulative wealth
    cum_full = np.exp(np.log1p(df["ret_wml"]).sum())
    cum_pre = np.exp(np.log1p(np.where(df["is_pretom"], df["ret_wml"], 0)).sum())
    cum_comp = np.exp(np.log1p(np.where(~df["is_pretom"], df["ret_wml"], 0)).sum())

    # Loser PreTOM stats
    loser_pre = df.loc[df["is_pretom"], "ret_loser"]
    loser_mean = loser_pre.mean() * 10000
    loser_t = loser_pre.mean() / (loser_pre.std() / np.sqrt(len(loser_pre)))

    # December
    df["month"] = df["date"].dt.month
    dec_loser = df.loc[df["is_pretom"] & (df["month"] == 12), "ret_loser"]
    dec_t = dec_loser.mean() / (dec_loser.std() / np.sqrt(len(dec_loser)))

    sep_loser = df.loc[df["is_pretom"] & (df["month"] == 9), "ret_loser"]
    sep_t = sep_loser.mean() / (sep_loser.std() / np.sqrt(len(sep_loser)))

    # DiD: read from output if available
    did_coef = "N/A"
    did_t = "N/A"
    did_path = os.path.join(OUTPUT_DIR, "table_did_t1.csv")
    if os.path.exists(did_path):
        did_df = pd.read_csv(did_path)
        triple = did_df[did_df["Variable"] == "triple"]
        if len(triple) > 0:
            did_coef = f"{triple.iloc[0]['Coefficient']:.1f}"
            did_t = f"{triple.iloc[0]['t-stat']:.2f}"

    print("\n\n")
    print("=" * 70)
    print("  VERIFICATION SUMMARY")
    print("  Compare these numbers to the paper")
    print("=" * 70)
    print(f"""
  Full WML cumulative wealth:       ${cum_full:.2f}
  PreTOM cumulative wealth:         ${cum_pre:.2f}
  Complementary cumulative wealth:  ${cum_comp:.2f}
  Loser-PreTOM mean (bps/day):      {loser_mean:.1f}
  Loser-PreTOM t-stat:              {loser_t:.2f}
  DiD coefficient (bps):            {did_coef}
  DiD t-stat:                       {did_t}
  December Loser-PreTOM t-stat:     {dec_t:.2f}
  September Loser-PreTOM t-stat:    {sep_t:.2f}

  Expected values (from the paper):
  Full WML cumulative wealth:       $45.89
  PreTOM cumulative wealth:         $18.11
  Complementary cumulative wealth:  $2.53
  Loser-PreTOM mean (bps/day):      -7.3
  Loser-PreTOM t-stat:              -2.95
  DiD coefficient (bps):            +46.8
  DiD t-stat:                       3.01
  December Loser-PreTOM t-stat:     0.28
  September Loser-PreTOM t-stat:    -3.36
""")

    print("  Note: Small discrepancies are expected due to differences in")
    print("  CRSP vintage, size screens, and exact breakpoint computation.")
    print("  See the paper's Internet Appendix for sensitivity analysis.")
    print("=" * 70)


def list_outputs():
    """List all files generated in the output directory."""
    print("\n  Output files generated:")
    if os.path.exists(OUTPUT_DIR):
        for f in sorted(os.listdir(OUTPUT_DIR)):
            path = os.path.join(OUTPUT_DIR, f)
            if os.path.isfile(path):
                size = os.path.getsize(path)
                print(f"    {f:40s}  {size:>10,} bytes")


def main():
    check_data()

    # Run all analysis scripts
    # (Uncomment the following to re-run everything; by default just prints summary)
    # run_all()

    # Print summary of key numbers
    print_summary()

    # List outputs
    list_outputs()

    print("\n  Replication complete.")


if __name__ == "__main__":
    main()

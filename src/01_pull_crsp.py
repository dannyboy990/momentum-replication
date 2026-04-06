"""
01_pull_crsp.py — WRDS Data Pull

Connects to WRDS, pulls CRSP daily and monthly stock files,
applies standard filters, saves as parquet.

Input:  WRDS credentials (set WRDS_USERNAME in config.py)
Output: data/crsp_daily.parquet, data/crsp_monthly.parquet
"""

import os
import sys
import time

import pandas as pd
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import WRDS_USERNAME, DATA_DIR, START_DATE, END_DATE


def connect_wrds():
    """Establish WRDS connection with helpful error message."""
    try:
        import wrds
        db = wrds.Connection(wrds_username=WRDS_USERNAME)
        print(f"Connected to WRDS as '{WRDS_USERNAME}'")
        return db
    except Exception as e:
        print(f"\nERROR: Could not connect to WRDS.\n")
        print(f"  {e}\n")
        print("To fix this:")
        print("  1. Set WRDS_USERNAME in config.py")
        print("  2. Ensure your WRDS subscription includes CRSP access")
        print("  3. Visit https://wrds-www.wharton.upenn.edu for account setup")
        print("  4. On first use, wrds will prompt for your password and cache it")
        sys.exit(1)


def pull_monthly(db):
    """Pull CRSP monthly stock file for momentum ranking."""
    print("\nPulling CRSP monthly file (crsp.msf + crsp.msenames)...")
    t0 = time.time()

    # Monthly returns with exchange/share type from header
    query = f"""
        SELECT a.permno, a.date, a.ret, a.prc, a.shrout,
               b.exchcd, b.shrcd
        FROM crsp.msf AS a
        INNER JOIN crsp.msenames AS b
            ON a.permno = b.permno
            AND a.date >= b.namedt
            AND a.date <= b.nameendt
        WHERE a.date >= '{START_DATE}'
          AND a.date <= '{END_DATE}'
          AND b.exchcd IN (1, 2, 3)
          AND b.shrcd IN (10, 11)
    """
    df = db.raw_sql(query, date_cols=["date"])

    # Basic cleaning
    df = df.dropna(subset=["ret"])
    df["me"] = df["prc"].abs() * df["shrout"]  # market equity (in $000s)
    df = df.dropna(subset=["me"])
    df = df[df["me"] > 0]

    # Exclude penny stocks (price < $1 at time of observation)
    df = df[df["prc"].abs() >= 1.0]

    elapsed = time.time() - t0
    print(f"  Pulled {len(df):,} monthly observations ({elapsed:.0f}s)")
    return df


def pull_daily(db):
    """Pull CRSP daily stock file."""
    print("\nPulling CRSP daily file (crsp.dsf)...")
    print("  This is a large download (~73M rows). Please be patient.")
    t0 = time.time()

    query = f"""
        SELECT a.permno, a.date, a.ret, a.prc, a.shrout, a.vol
        FROM crsp.dsf AS a
        INNER JOIN crsp.msenames AS b
            ON a.permno = b.permno
            AND a.date >= b.namedt
            AND a.date <= b.nameendt
        WHERE a.date >= '{START_DATE}'
          AND a.date <= '{END_DATE}'
          AND b.exchcd IN (1, 2, 3)
          AND b.shrcd IN (10, 11)
    """
    df = db.raw_sql(query, date_cols=["date"])

    # Basic cleaning
    df = df.dropna(subset=["ret"])

    # Market cap for value-weighting
    df["me"] = df["prc"].abs() * df["shrout"]

    elapsed = time.time() - t0
    print(f"  Pulled {len(df):,} daily observations ({elapsed:.0f}s)")
    return df


def main():
    os.makedirs(DATA_DIR, exist_ok=True)

    daily_path = os.path.join(DATA_DIR, "crsp_daily.parquet")
    monthly_path = os.path.join(DATA_DIR, "crsp_monthly.parquet")

    # Check if files already exist
    if os.path.exists(daily_path) and os.path.exists(monthly_path):
        print("Data files already exist:")
        print(f"  {daily_path}")
        print(f"  {monthly_path}")
        print("Delete them and re-run to re-download.")
        return

    db = connect_wrds()

    try:
        # Pull monthly data (for portfolio formation)
        df_monthly = pull_monthly(db)
        df_monthly.to_parquet(monthly_path, index=False)
        print(f"  Saved: {monthly_path} ({len(df_monthly):,} rows)")

        # Pull daily data (for returns)
        df_daily = pull_daily(db)
        df_daily.to_parquet(daily_path, index=False)
        print(f"  Saved: {daily_path} ({len(df_daily):,} rows)")

    finally:
        db.close()

    print("\nDone. Proceed to 02_build_portfolios.py")


if __name__ == "__main__":
    main()

"""
01_pull_crsp.py — WRDS Data Pull

Connects to WRDS, pulls CRSP daily and monthly stock files using the
CIZ Flat File Format 2.0 tables, applies filters matching the paper's
Internet Appendix Section IA.1, saves as parquet.

Input:  WRDS credentials (set WRDS_USERNAME in config.py)
Output: data/crsp_daily.parquet, data/crsp_monthly.parquet
"""

import os
import sys
import time

import pandas as pd
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import WRDS_USERNAME, DATA_DIR


# ── CRSP CIZ filter values (Internet Appendix IA.1) ─────────────────────
# These replicate the exact sample restrictions in the paper.
CIZ_FILTERS = """
    h.sharetype = 'NS'
    AND h.securitytype = 'EQTY'
    AND h.securitysubtype = 'COM'
    AND h.usincflg = 'Y'
    AND h.issuertype IN ('ACOR', 'CORP')
    AND h.primaryexch IN ('N', 'A', 'Q')
    AND h.conditionaltype = 'RW'
    AND h.tradingstatusflg = 'A'
"""


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


def pull_daily(db):
    """
    Pull CRSP daily stock data using CIZ format tables.

    Tables:
      crsp.stkdlysecuritydata  — daily returns, prices, volume
      crsp.stksecurityinfohdr  — security header for sample filters

    Filters match Internet Appendix Section IA.1 exactly.
    Date range starts at 1978-12-29 to allow momentum signal construction
    (12-month lookback) for holding months beginning January 1980.
    """
    print("\nPulling CRSP daily file (CIZ format)...")
    print("  This is a large download. Please be patient.")
    t0 = time.time()

    query = f"""
        SELECT d.permno,
               d.dlycaldt AS date,
               d.dlyret AS ret,
               d.dlyretx AS retx,
               d.dlyprc AS prc,
               d.dlyprevcap AS prevcap,
               d.dlycap AS cap,
               d.dlyvol AS vol,
               d.dlybid AS bid,
               d.dlyask AS ask,
               d.dlynumtrd AS numtrd,
               d.dlyprcvol AS prcvol,
               d.dlyretmissflg AS retmissflg,
               h.primaryexch AS exchcd
        FROM crsp.stkdlysecuritydata AS d
        INNER JOIN crsp.stksecurityinfohist AS h
            ON d.permno = h.permno
            AND d.dlycaldt >= h.secinfostartdt
            AND d.dlycaldt <= h.secinfoenddt
        WHERE d.dlycaldt >= '1978-12-29'
          AND d.dlycaldt <= '2025-12-31'
          AND {CIZ_FILTERS}
    """
    df = db.raw_sql(query, date_cols=["date"])

    # Exclude observations with missing-return flags per IA.1
    bad_flags = {'MV', 'NS', 'NT', 'RA', 'GP', 'MP', 'DG', 'DM', 'DP'}
    if "retmissflg" in df.columns:
        mask = df["retmissflg"].isna() | ~df["retmissflg"].str.strip().isin(bad_flags)
        n_before = len(df)
        df = df[mask]
        print(f"  Excluded {n_before - len(df):,} rows with bad DlyRetMissFlg")

    df = df.dropna(subset=["ret"])

    elapsed = time.time() - t0
    print(f"  Pulled {len(df):,} daily observations ({elapsed:.0f}s)")
    print(f"  Date range: {df['date'].min()} to {df['date'].max()}")
    print(f"  Unique permnos: {df['permno'].nunique():,}")
    return df


def pull_monthly(db):
    """
    Pull CRSP monthly stock data using CIZ format tables.
    Used for momentum signal construction and portfolio formation.
    """
    print("\nPulling CRSP monthly file (CIZ format)...")
    t0 = time.time()

    query = f"""
        SELECT m.permno,
               m.mthcaldt AS date,
               m.mthret AS ret,
               m.mthprc AS prc,
               m.mthcap AS cap,
               m.mthprevcap AS prevcap,
               h.primaryexch AS exchcd
        FROM crsp.stkmthsecuritydata AS m
        INNER JOIN crsp.stksecurityinfohist AS h
            ON m.permno = h.permno
            AND m.mthcaldt >= h.secinfostartdt
            AND m.mthcaldt <= h.secinfoenddt
        WHERE m.mthcaldt >= '1978-12-01'
          AND m.mthcaldt <= '2025-12-31'
          AND {CIZ_FILTERS}
    """
    df = db.raw_sql(query, date_cols=["date"])
    df = df.dropna(subset=["ret"])

    elapsed = time.time() - t0
    print(f"  Pulled {len(df):,} monthly observations ({elapsed:.0f}s)")
    print(f"  Date range: {df['date'].min()} to {df['date'].max()}")
    print(f"  Unique permnos: {df['permno'].nunique():,}")
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

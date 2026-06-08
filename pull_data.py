"""
pull_data.py - Pull all raw inputs needed by build_panel.py.

THEORETICAL: the WRDS queries below are written against Internet Appendix
Section 1 and the CRSP Flat File Format 2.0 (CIZ) schema. They have NOT
been executed end-to-end against a live WRDS subscription — verify the
table and column names against your access before running for real.

What this writes (all under <root>/data/):
  crsp_daily_ciz.csv                  - CRSP daily, CIZ format, 1925-12-31 onward
                                        (1925-12-31 lets 1927 momentum be
                                        constructed from a full 12-2 history)
  crsp_trading_days.csv               - unique CRSP trading-day calendar
  sp500constituents.csv               - CRSP S&P 500 index constituents
  taq_iid.parquet                     - WRDS TAQ Intraday Indicators, PERMNO-linked
  Prior_2-12_Breakpoints.csv          - Ken French NYSE momentum breakpoints
  F-F_Research_Data_Factors_daily.csv - Ken French daily factors

The 13F holdings pull is deliberately omitted: the published paper does
not use 13F.

Usage:
  python pull_data.py [--root PATH] [--what crsp|taq|sp500|french|all]
                      [--start-date 1925-12-31] [--end-date 2025-12-31]

Requires:
  pip install wrds pandas pyarrow requests
  WRDS account with CRSP and TAQ access. The wrds package will prompt
  for credentials on first connect and cache them via pgpass.
"""

from __future__ import annotations

import argparse
import io
import sys
import zipfile
from pathlib import Path

import pandas as pd
import requests


# ─────────────────────────────────────────────────────────────────────────────
#  CRSP daily, CIZ Flat File Format 2.0
# ─────────────────────────────────────────────────────────────────────────────

CIZ_FILTERS_SQL = """
    h.sharetype = 'NS'
    AND h.securitytype = 'EQTY'
    AND h.securitysubtype = 'COM'
    AND h.usincflg = 'Y'
    AND h.issuertype IN ('ACOR', 'CORP')
    AND h.primaryexch IN ('N', 'A', 'Q')
    AND h.conditionaltype = 'RW'
    AND h.tradingstatusflg = 'A'
"""


def pull_crsp_daily(db, start_date: str, end_date: str, out_path: Path) -> None:
    """CRSP daily file with all columns build_panel.py expects.

    Columns mapped to CIZ names so that the output CSV is readable directly
    by build_panel.py without renaming.
    """
    print(f"\n[crsp] Pulling CRSP daily {start_date} -> {end_date}")
    print("[crsp] Large download — expect minutes to hours depending on connection.")

    query = f"""
        SELECT
            d.permno              AS "PERMNO",
            d.dlycaldt            AS "DlyCalDt",
            d.dlyret              AS "DlyRet",
            d.dlyprc              AS "DlyPrc",
            d.shrout              AS "ShrOut",
            h.primaryexch         AS "PrimaryExch",
            d.dlyretmissflg       AS "DlyRetMissFlg",
            h.securitytype        AS "SecurityType",
            h.securitysubtype     AS "SecuritySubType",
            h.sharetype           AS "ShareType",
            h.usincflg            AS "USIncFlg",
            h.issuertype          AS "IssuerType",
            h.tradingstatusflg    AS "TradingStatusFlg",
            h.conditionaltype     AS "ConditionalType",
            d.dlycap              AS "DlyCap",
            d.dlyprevcap          AS "DlyPrevCap",
            d.dlybid              AS "DlyBid",
            d.dlyask              AS "DlyAsk"
        FROM crsp.stkdlysecuritydata AS d
        INNER JOIN crsp.stksecurityinfohist AS h
          ON d.permno = h.permno
          AND d.dlycaldt >= h.secinfostartdt
          AND d.dlycaldt <= h.secinfoenddt
        WHERE d.dlycaldt BETWEEN '{start_date}' AND '{end_date}'
          AND {CIZ_FILTERS_SQL}
    """
    df = db.raw_sql(query, date_cols=["DlyCalDt"])
    print(f"[crsp] {len(df):,} rows, {df['PERMNO'].nunique():,} permnos")
    df.to_csv(out_path, index=False)
    print(f"[crsp] -> {out_path}")


def pull_trading_days(db, start_date: str, end_date: str, out_path: Path) -> None:
    """Unique CRSP trading-day calendar — used for trading-day expansion."""
    print(f"\n[trading_days] Pulling CRSP trading calendar {start_date} -> {end_date}")
    query = f"""
        SELECT DISTINCT dlycaldt AS "DlyCalDt"
        FROM crsp.stkdlysecuritydata
        WHERE dlycaldt BETWEEN '{start_date}' AND '{end_date}'
        ORDER BY dlycaldt
    """
    df = db.raw_sql(query, date_cols=["DlyCalDt"])
    print(f"[trading_days] {len(df):,} unique trading days")
    df.to_csv(out_path, index=False)
    print(f"[trading_days] -> {out_path}")


def pull_sp500_constituents(db, start_date: str, end_date: str, out_path: Path) -> None:
    """CRSP S&P 500 index constituents (used for in_sp500 flag).

    The CIZ-era table is crsp.dsp500list_v2 (PERMNO + start/end dates per
    constituent spell). We expand to a daily PERMNO-date grid by joining
    with the trading calendar.
    """
    print(f"\n[sp500] Pulling S&P 500 constituency {start_date} -> {end_date}")
    query = f"""
        SELECT
            sp.permno                      AS "PERMNO",
            cal.dlycaldt                   AS "DlyCalDt"
        FROM crsp.dsp500list_v2 AS sp
        INNER JOIN crsp.stkdlysecuritydata AS cal
          ON cal.dlycaldt BETWEEN sp.start AND sp.ending
        WHERE cal.dlycaldt BETWEEN '{start_date}' AND '{end_date}'
        GROUP BY sp.permno, cal.dlycaldt
    """
    df = db.raw_sql(query, date_cols=["DlyCalDt"])
    print(f"[sp500] {len(df):,} permno-day pairs")
    df.to_csv(out_path, index=False)
    print(f"[sp500] -> {out_path}")


# ─────────────────────────────────────────────────────────────────────────────
#  TAQ Intraday Indicators (Lee-Ready buy/sell volumes), with PERMNO link
# ─────────────────────────────────────────────────────────────────────────────

def pull_taq(db, out_path: Path,
             start_date: str = "2003-09-10",
             end_date: str = "2022-10-27") -> None:
    """WRDS TAQ Intraday Indicators (IID), PERMNO-linked via CRSP-TAQ link.

    Columns produced (matching what build_panel.py expects):
        DATE, PERMNO,
        SellVol_LR, BuyVol_LR, total_vol,
        SellVol_Inst50k, BuyVol_Inst50k, total_vol_Inst50k

    The IID tables on WRDS are keyed by SYM_ROOT / SYM_SUFFIX, not PERMNO.
    The link comes from crsp_a_ccm.ccmxpf_lnkhist or wrds_taq.taq_link
    (depending on subscription). Schema differs across years; the
    multi-year aggregation below is the cleanest pattern, but you may
    need to adapt the table names to your access.
    """
    print(f"\n[taq] Pulling TAQ Intraday Indicators {start_date} -> {end_date}")

    # Note: WRDS TAQ IID tables are partitioned by year as
    #   taqmsec.iid_<YYYYMMDD> (millisecond) or wrdstaq.iid_<YYYY> (consolidated)
    # The exact name depends on subscription. Verify with:
    #   SELECT table_name FROM information_schema.tables
    #     WHERE table_schema IN ('taqmsec','wrdstaq','taq')
    #     AND table_name LIKE 'iid%'
    #   ORDER BY table_name DESC LIMIT 5;
    iid_table = "taqmsec.iid"  # placeholder — confirm against your access

    query = f"""
        WITH iid AS (
            SELECT
                t.date                         AS "DATE",
                t.sym_root, t.sym_suffix,
                t.sellvol_lr                   AS "SellVol_LR",
                t.buyvol_lr                    AS "BuyVol_LR",
                t.total_vol                    AS total_vol,
                t.sellvol_inst50k              AS "SellVol_Inst50k",
                t.buyvol_inst50k               AS "BuyVol_Inst50k",
                t.total_vol_inst50k            AS total_vol_Inst50k
            FROM {iid_table} AS t
            WHERE t.date BETWEEN '{start_date}' AND '{end_date}'
        ),
        link AS (
            SELECT permno, sym_root, sym_suffix, datestart, dateend
            FROM wrds_taq.taq_link
        )
        SELECT
            i."DATE",
            l.permno                            AS "PERMNO",
            i."SellVol_LR", i."BuyVol_LR",
            i.total_vol,
            i."SellVol_Inst50k", i."BuyVol_Inst50k",
            i.total_vol_Inst50k
        FROM iid AS i
        INNER JOIN link AS l
          ON l.sym_root = i.sym_root
         AND COALESCE(l.sym_suffix, '') = COALESCE(i.sym_suffix, '')
         AND i."DATE" BETWEEN l.datestart AND l.dateend
    """
    df = db.raw_sql(query, date_cols=["DATE"])
    print(f"[taq] {len(df):,} rows, {df['PERMNO'].nunique():,} permnos")
    df.to_parquet(out_path, index=False)
    print(f"[taq] -> {out_path}")


# ─────────────────────────────────────────────────────────────────────────────
#  Ken French (no WRDS — public CSVs)
# ─────────────────────────────────────────────────────────────────────────────

FRENCH_BASE = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp"

FRENCH_FILES = {
    "Prior_2-12_Breakpoints.csv": f"{FRENCH_BASE}/Prior_2-12_Breakpoints_CSV.zip",
    "F-F_Research_Data_Factors_daily.csv": f"{FRENCH_BASE}/F-F_Research_Data_Factors_daily_CSV.zip",
}


def pull_french(out_dir: Path) -> None:
    """Download Ken French momentum breakpoints + daily FF factors."""
    for fname, url in FRENCH_FILES.items():
        out_path = out_dir / fname
        print(f"\n[french] {url}")
        resp = requests.get(url, timeout=120)
        resp.raise_for_status()
        with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
            inner = [n for n in zf.namelist() if n.lower().endswith(".csv")][0]
            with zf.open(inner) as f:
                out_path.write_bytes(f.read())
        print(f"[french] -> {out_path}")


# ─────────────────────────────────────────────────────────────────────────────
#  CLI
# ─────────────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--root", type=Path,
                   default=Path(__file__).resolve().parent,
                   help="replication root (default: directory containing pull_data.py)")
    p.add_argument("--what", choices=["crsp", "taq", "sp500", "french", "all"],
                   default="all",
                   help="which datasets to pull (default: all)")
    p.add_argument("--start-date", default="1925-12-31",
                   help="CRSP daily pull start (YYYY-MM-DD). "
                        "Default 1925-12-31 — gives a full 12-2 history for 1927+ momentum.")
    p.add_argument("--end-date", default="2025-12-31",
                   help="CRSP daily pull end (YYYY-MM-DD). Default 2025-12-31.")
    p.add_argument("--taq-start", default="2003-09-10",
                   help="TAQ IID start date (YYYY-MM-DD). Default 2003-09-10.")
    p.add_argument("--taq-end", default="2022-10-27",
                   help="TAQ IID end date (YYYY-MM-DD). Default 2022-10-27.")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    data_dir = args.root.resolve() / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    needs_wrds = args.what in ("crsp", "taq", "sp500", "all")
    db = None
    if needs_wrds:
        try:
            import wrds
        except ImportError:
            sys.exit("ERROR: `pip install wrds` is required for CRSP/TAQ/SP500 pulls.")
        db = wrds.Connection()
        print(f"[wrds] connected as {db._username}")

    if args.what in ("crsp", "all"):
        pull_crsp_daily(db, args.start_date, args.end_date,
                        data_dir / "crsp_daily_ciz.csv")
        pull_trading_days(db, args.start_date, args.end_date,
                          data_dir / "crsp_trading_days.csv")
    if args.what in ("sp500", "all"):
        pull_sp500_constituents(db, args.start_date, args.end_date,
                                data_dir / "sp500constituents.csv")
    if args.what in ("taq", "all"):
        pull_taq(db, data_dir / "taq_iid.parquet",
                 start_date=args.taq_start, end_date=args.taq_end)
    if args.what in ("french", "all"):
        pull_french(data_dir)

    if db is not None:
        db.close()
    print("\n[done] All requested pulls complete. "
          "Next: `python build_panel.py --root . --start-date 1926-01-01`")


if __name__ == "__main__":
    main()

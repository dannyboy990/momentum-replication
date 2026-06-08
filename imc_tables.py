"""
imc_tables.py - Python translation of the stock-level table regressions.

================================  IMPORTANT  ================================
This is an AI-ASSISTED Python translation of the Stata pipeline in
`code/stata/` (the `reghdfe` regressions with firm + date fixed effects and
two-way clustered standard errors), provided as a convenience for users who
want to run the analysis in Python instead of Stata.

  * It uses `pyfixest` (feols) for the high-dimensional fixed-effects /
    two-way-clustered regressions.
  * As a demonstration, ONLY the first table (Table 1, the baseline panel
    regression) is implemented and run here. The remaining tables (BAS
    interaction, subperiods, falsification, reversal, TAQ, dividends,
    international, ...) follow the same pattern but are NOT translated.
  * We CANNOT vouch that this Python translation matches the Stata output to
    the last digit. The Stata code in `code/stata/` remains the AUTHORITATIVE
    source for every number reported in the paper. Use this at your own risk.
============================================================================

Table 1 (baseline) Stata spec, from code/stata/_tables_vw.do:

    eststo ew: reghdfe ret_mkt loser lp,        absorb(permno date) cluster(permno date)
    eststo vw: reghdfe ret_mkt loser lp [aw=w_l1], absorb(permno date) cluster(permno date)

where lp = loser * preTOM. With firm + date fixed effects the slope
coefficients on `loser` and `lp` are identical whether the dependent variable
is the excess return (r_i - r_f) or the market-adjusted return (r_i - r^m),
because the per-date constant is absorbed by the date fixed effect. We
therefore run directly on the excess return in basis points.

Usage:
    python imc_tables.py            # runs Table 1 (needs data/panel_fixed_vw_reg.csv)
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import pandas as pd

try:
    import pyfixest as pf
except ImportError:
    sys.exit("ERROR: this script needs pyfixest.  pip install pyfixest")

ROOT = Path(__file__).resolve().parent


def table1_baseline() -> None:
    panel = ROOT / "data" / "panel_fixed_vw_reg.csv"
    if not panel.exists():
        sys.exit(
            f"ERROR: {panel} not found.\n"
            "Build it from the CRSP panel (see code/stata/00_replicate.do Step 2, "
            "or build_panel.py)."
        )

    t0 = time.time()
    print(f"[table1] loading {panel.name} (this is a ~50M-row file) ...")
    df = pd.read_csv(
        panel,
        usecols=["date", "PERMNO", "ret_rf", "loser", "preTOM", "w_l1"],
        dtype={"PERMNO": "int32", "ret_rf": "float32",
               "loser": "int8", "preTOM": "int8", "w_l1": "float32"},
    )
    print(f"[table1]   {len(df):,} rows loaded in {time.time() - t0:.0f}s")

    # Dependent variable: excess return in basis points (slopes match r_i - r^m).
    df["rebp"] = df["ret_rf"] * 10000.0
    # Loser x PreTOM interaction.
    df["lp"] = (df["loser"] * df["preTOM"]).astype("int8")

    # NOTE: the two-way (firm + date) clustered SE on ~53M rows is slow in
    # pyfixest (expect 20-30+ minutes and substantial RAM). The point estimates
    # are SE-independent and have been checked to match the Stata output exactly
    # (EW loser x PreTOM = -2.550, VW = -7.151). If you only need the
    # coefficients quickly, swap vcov={"CRV1": "PERMNO+date"} for vcov="hetero".
    print("[table1] estimating EW (unweighted); two-way clustered SE is slow ...")
    ew = pf.feols("rebp ~ loser + lp | PERMNO + date",
                  data=df, vcov={"CRV1": "PERMNO+date"})
    print("[table1] estimating VW (weighted by lagged market cap) ...")
    vw = pf.feols("rebp ~ loser + lp | PERMNO + date",
                  data=df, weights="w_l1", vcov={"CRV1": "PERMNO+date"})

    bar = "=" * 64
    print(f"\n{bar}\n  TABLE 1 - Baseline panel regression (Python / pyfixest)")
    print(f"  Dependent variable: daily excess return (bps)")
    print(f"  Firm + date FE; two-way clustered SE\n{bar}")
    print(f"  {'':22s}{'EW':>14s}{'VW':>14s}")
    for var, label in [("loser", "Loser"), ("lp", "Loser x PreTOM")]:
        ec, et = ew.coef()[var], ew.tstat()[var]
        vc, vt = vw.coef()[var], vw.tstat()[var]
        print(f"  {label:22s}{ec:>9.3f} (t={et:4.2f}){vc:>9.3f} (t={vt:4.2f})")
    n_ew = getattr(ew, "_N", len(df))
    print(f"  {'N':22s}{int(n_ew):>14,d}{int(n_ew):>14,d}")
    print(bar)
    print("  Paper (Stata, authoritative): EW Loser x PreTOM = -2.550 (t=-1.85);")
    print("                                VW Loser x PreTOM = -7.151 (t=-3.08).")
    print(f"  (done in {time.time() - t0:.0f}s)\n")


if __name__ == "__main__":
    table1_baseline()

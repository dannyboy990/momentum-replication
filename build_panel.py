#!/usr/bin/env python3
"""
build_panel.py - Build the fixed-monthly-sorting CRSP+TAQ panel.

Implements Internet Appendix Section 1 step-for-step (CIZ filters, trading-day
expansion, month-relative t, 12-2 momentum with DlyRetMissFlg validity,
French NYSE Prior 2-12 breakpoints, lagged-mcap weights, BAS, S&P 500 flag,
FF factors, TAQ Lee-Ready merge).

Original implementation by Filipp Dokienko (turn-of-month-momentum project).
Adapted for the replication package: argparse-based paths, SMB/HML retained
in the output panel, runtime --start-date so the same script handles the
1980+ window or the full-sample 1927+ window.

Inputs (in <root>/data/):
  crsp_daily_ciz.csv         - CRSP daily, CIZ format (from pull_data.py)
  crsp_trading_days.csv      - CRSP trading-day calendar
  Prior_2-12_Breakpoints.csv - Ken French NYSE breakpoints
  F-F_Research_Data_Factors_daily.csv - Ken French daily factors
  sp500constituents.csv      - CRSP S&P 500 index constituents
  taq_iid.parquet            - WRDS TAQ Intraday Indicators (PERMNO-linked)

Output:
  <root>/data/crsp_fixed_sorting_panel.parquet - read by imc.py {build,tc,holding}

Usage:
  python build_panel.py [--root PATH] [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD]
"""

from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path

import polars as pl
import polars.selectors as cs


# =========================
# CONFIG (manual edits)
# =========================
ALLOW_NA_AND_MP = True
WRITE_LOGS = True
USE_PARQUET_CHECKPOINTS = True
RESET_CHECKPOINTS = True

# Keep same notebook default unless manually changed.
END_DATE = dt.date(2025, 12, 31)

# Optional override. If None, uses last trading day in 1978 from input CRSP.
START_DATE_OVERRIDE: dt.date | None = None


# This list is the only place where allowed flags are set.
ALLOWED_FLAGS = ["NA", "MP"] if ALLOW_NA_AND_MP else ["NA"]
RUN_TAG = "na_mp" if ALLOW_NA_AND_MP else "na_only"


def collect_streaming_safe(lf: pl.LazyFrame) -> pl.DataFrame:
    """Collect lazily with streaming fallback for compatibility across Polars versions."""
    try:
        return lf.collect(engine="streaming")
    except Exception:
        try:
            return lf.collect(streaming=True)
        except Exception:
            return lf.collect()


def write_lazy_parquet(lf: pl.LazyFrame, out_path: Path, label: str) -> None:
    """Write a LazyFrame to parquet, preferring streaming sink when available."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        lf.sink_parquet(str(out_path), compression="zstd")
    except Exception:
        collect_streaming_safe(lf).write_parquet(str(out_path))
    print(f"[parquet] {label}: {out_path}")


def checkpoint_lazy(lf: pl.LazyFrame, out_path: Path, label: str) -> pl.LazyFrame:
    """Optionally checkpoint a LazyFrame to parquet and continue from a fresh scan."""
    if not USE_PARQUET_CHECKPOINTS:
        return lf
    write_lazy_parquet(lf, out_path, label)
    return pl.scan_parquet(str(out_path))


def safe_div(num: pl.Expr, den: pl.Expr) -> pl.Expr:
    """Division that returns null when denominator is null/zero."""
    return pl.when(den.is_not_null() & (den != 0)).then(num / den).otherwise(None)


def summarize_step(lf: pl.LazyFrame, step: str, rule: str) -> dict:
    s = collect_streaming_safe(
        lf.select([
            pl.len().alias("n_rows"),
            pl.col("PERMNO").n_unique().alias("n_permno"),
            pl.col("date").n_unique().alias("n_trading_days"),
            pl.struct(["PERMNO", "date"]).n_unique().alias("n_permno_date_pairs"),
        ])
    ).to_dicts()[0]
    s["step"] = step
    s["rule"] = rule
    return s


def build_momentum_variant(lf_input: pl.LazyFrame, allow_flags: list[str]) -> dict[str, pl.LazyFrame]:
    not_allow_universe = ["MV", "NS", "NT", "RA", "GP", "MP", "DG", "DM", "DP"]
    not_allow_flags = [f for f in not_allow_universe if f not in allow_flags]

    ret = pl.col("RET").cast(pl.Float64).fill_nan(None)
    flag = pl.col("DlyRetMissFlg")
    flag_allow = flag.is_in(allow_flags)
    flag_not_allow = flag.is_not_null() & flag.is_in(not_allow_flags)
    both_missing = ret.is_null() & flag.is_null()

    ok_day = flag_allow | (ret.is_not_null() & flag.is_null())
    bad_day = flag_not_allow
    g_val = (1.0 + ret).fill_null(1.0)

    lf_base = (
        lf_input
        .with_columns([
            pl.col("date").cast(pl.Date),
            pl.col("date").dt.truncate("1mo").alias("ym"),
            ok_day.cast(pl.Int16).alias("_ok"),
            bad_day.cast(pl.Int16).alias("_bad"),
            both_missing.cast(pl.Int16).alias("_bm"),
            (g_val == 0.0).cast(pl.Int16).alias("_zero"),
            g_val.alias("_G"),
        ])
        .sort(["PERMNO", "date"])
        .with_columns([
            pl.int_range(1, pl.len() + 1).over("PERMNO").alias("_idx"),
            pl.col("_G").cum_prod().over("PERMNO").alias("_cumG"),
            pl.col("_ok").cum_sum().over("PERMNO").alias("_ok_cum"),
            pl.col("_bad").cum_sum().over("PERMNO").alias("_bad_cum"),
            pl.col("_bm").cum_sum().over("PERMNO").alias("_bm_cum"),
            pl.col("_zero").cum_sum().over("PERMNO").alias("_zero_cum"),
        ])
    )

    monthly = (
        lf_base
        .group_by(["PERMNO", "ym"])
        .agg([
            pl.col("date").min().alias("month_start"),
            pl.col("date").max().alias("month_end"),
            pl.col("_idx").sort_by("date").last().alias("end_idx"),
            pl.col("_cumG").sort_by("date").last().alias("end_cumG"),
            pl.col("_ok_cum").sort_by("date").last().alias("end_ok"),
            pl.col("_bad_cum").sort_by("date").last().alias("end_bad"),
            pl.col("_bm_cum").sort_by("date").last().alias("end_bm"),
            pl.col("_zero_cum").sort_by("date").last().alias("end_zero"),
        ])
        .with_columns([
            pl.col("ym").dt.offset_by("2mo").alias("target_ym"),
            pl.col("ym").dt.offset_by("-11mo").alias("prev_ym"),
        ])
    )

    mom_monthly = (
        monthly
        .join(
            monthly.select([
                pl.col("PERMNO"),
                pl.col("ym").alias("prev_ym"),
                pl.col("end_idx").alias("prev_idx"),
                pl.col("end_cumG").alias("prev_cumG"),
                pl.col("end_ok").alias("prev_ok"),
                pl.col("end_bad").alias("prev_bad"),
                pl.col("end_bm").alias("prev_bm"),
                pl.col("end_zero").alias("prev_zero"),
            ]),
            on=["PERMNO", "prev_ym"],
            how="left",
        )
        .with_columns([
            (pl.col("end_idx") - pl.col("prev_idx")).alias("_win_days"),
            (pl.col("end_ok") - pl.col("prev_ok")).alias("_ok_win"),
            (pl.col("end_bad") - pl.col("prev_bad")).alias("_bad_win"),
            (pl.col("end_bm") - pl.col("prev_bm")).alias("_bm_win"),
            (pl.col("end_zero") - pl.col("prev_zero")).alias("_zero_win"),
            ((pl.col("end_cumG") / pl.col("prev_cumG")) - 1.0).alias("_mom_raw"),
        ])
        .with_columns(
            pl.when(pl.col("prev_cumG").is_null()).then(1)
            .when(pl.col("_bad_win") > 0).then(2)
            .when(pl.col("_bm_win") > 0).then(3)
            .when(pl.col("_ok_win") != pl.col("_win_days")).then(4)
            .when(pl.col("_zero_win") > 0).then(5)
            .otherwise(0)
            .cast(pl.Int8)
            .alias("mom_code")
        )
        .with_columns(pl.when(pl.col("mom_code") == 0).then(pl.col("_mom_raw")).otherwise(None).alias("mom"))
        .select(["PERMNO", pl.col("target_ym").alias("ym"), "mom", "mom_code"])
    )

    lf_with_mom = (
        lf_base
        .join(mom_monthly, on=["PERMNO", "ym"], how="left")
        .with_columns(pl.coalesce([pl.col("mom_code"), pl.lit(1, dtype=pl.Int8)]).alias("mom_code"))
        .select((~cs.starts_with("_")))
    )

    lf_after_mom = lf_with_mom.filter(pl.col("mom_code") == 0)
    lf_after_cap = lf_after_mom.filter(pl.col("DlyPrevCap").is_not_null())
    lf_final = lf_after_cap.filter(pl.col("RET").is_not_null())

    return {
        "lf_with_mom": lf_with_mom,
        "lf_after_mom": lf_after_mom,
        "lf_after_cap": lf_after_cap,
        "lf_final": lf_final,
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--root", type=Path,
                   default=Path(__file__).resolve().parent,
                   help="replication root (default: directory containing build_panel.py)")
    p.add_argument("--start-date", type=str, default=None,
                   help="earliest date to retain (YYYY-MM-DD). "
                        "Default: earliest date in input CSV. "
                        "For full-sample 1927+ analysis, pull CRSP from 1925-12-31 "
                        "and pass --start-date 1926-01-01.")
    p.add_argument("--end-date", type=str, default="2025-12-31",
                   help="latest date to retain (YYYY-MM-DD). Default: 2025-12-31.")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    root = args.root.resolve()

    # Inputs used by the pipeline.
    data_dir = root / "data"
    input_crsp_csv = data_dir / "crsp_daily_ciz.csv"
    input_trading_days_csv = data_dir / "crsp_trading_days.csv"
    breakpoints_csv = data_dir / "Prior_2-12_Breakpoints.csv"
    factors_csv = data_dir / "F-F_Research_Data_Factors_daily.csv"
    sp500_csv = data_dir / "sp500constituents.csv"
    taq_input = data_dir / "taq_iid.parquet"

    out_dir = data_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_dir = out_dir / f"_tmp_checkpoints_{RUN_TAG}"
    if USE_PARQUET_CHECKPOINTS:
        checkpoint_dir.mkdir(parents=True, exist_ok=True)
        if RESET_CHECKPOINTS:
            for p in checkpoint_dir.glob("*.parquet"):
                p.unlink(missing_ok=True)

    out_panel_with_taq = out_dir / "crsp_fixed_sorting_panel.parquet"
    out_taq_summary_csv = out_dir / f"taq_merge_summary_{RUN_TAG}.csv"
    out_taq_coverage_csv = out_dir / f"taq_merge_coverage_by_year_{RUN_TAG}.csv"

    required_paths = [
        input_crsp_csv,
        input_trading_days_csv,
        breakpoints_csv,
        factors_csv,
        sp500_csv,
        taq_input,
    ]
    for p in required_paths:
        if not p.exists():
            raise FileNotFoundError(f"Missing required input: {p}")

    print({
        "root": str(root),
        "run_tag": RUN_TAG,
        "allowed_flags": ALLOWED_FLAGS,
        "write_logs": WRITE_LOGS,
        "use_parquet_checkpoints": USE_PARQUET_CHECKPOINTS,
        "checkpoint_dir": str(checkpoint_dir),
        "out_panel_with_taq": str(out_panel_with_taq),
    })

    # Stage 1: build the filtered CRSP panel and attrition table.
    cols = [
        pl.col("DlyCalDt").cast(pl.Date).alias("date"),
        pl.col("PERMNO").cast(pl.Int64),
        pl.col("DlyRet").cast(pl.Float64).alias("RET"),
        pl.col("DlyPrc").cast(pl.Float64).alias("PRC"),
        pl.col("ShrOut").cast(pl.Float64),
        pl.col("PrimaryExch"),
        pl.col("DlyRetMissFlg").cast(pl.Utf8),
        pl.col("SecurityType"),
        pl.col("SecuritySubType"),
        pl.col("ShareType"),
        pl.col("USIncFlg"),
        pl.col("IssuerType"),
        pl.col("TradingStatusFlg"),
        pl.col("ConditionalType"),
        pl.col("DlyCap").cast(pl.Float64),
        pl.col("DlyPrevCap").cast(pl.Float64),
        pl.col("DlyBid").cast(pl.Float64),
        pl.col("DlyAsk").cast(pl.Float64),
    ]

    csv_schema_overrides = {
        "DlyCalDt": pl.Utf8,
        "PERMNO": pl.Int64,
        "DlyRet": pl.Float64,
        "DlyPrc": pl.Float64,
        "ShrOut": pl.Float64,
        "PrimaryExch": pl.Utf8,
        "DlyRetMissFlg": pl.Utf8,
        "SecurityType": pl.Utf8,
        "SecuritySubType": pl.Utf8,
        "ShareType": pl.Utf8,
        "USIncFlg": pl.Utf8,
        "IssuerType": pl.Utf8,
        "TradingStatusFlg": pl.Utf8,
        "ConditionalType": pl.Utf8,
        "DlyCap": pl.Float64,
        "DlyPrevCap": pl.Float64,
        "DlyBid": pl.Float64,
        "DlyAsk": pl.Float64,
    }

    lf_raw = (
        pl.scan_csv(
            str(input_crsp_csv),
            schema_overrides=csv_schema_overrides,
            infer_schema_length=0,
            try_parse_dates=False,
            low_memory=True,
        )
        .select(cols)
    )

    if args.start_date is not None:
        start_date = dt.date.fromisoformat(args.start_date)
    elif START_DATE_OVERRIDE is not None:
        start_date = START_DATE_OVERRIDE
    else:
        earliest = collect_streaming_safe(
            lf_raw.select(pl.col("date").min().alias("d"))
        )["d"][0]
        if earliest is None:
            raise ValueError("Input CSV is empty; cannot infer start date.")
        start_date = earliest
    end_date = dt.date.fromisoformat(args.end_date) if args.end_date else END_DATE
    print(f"Using start_date={start_date}, end_date={end_date}")

    logs = [] if WRITE_LOGS else None
    if WRITE_LOGS:
        logs.append(summarize_step(lf_raw, "0_raw_input", "No filters; selected/cast columns only"))

    lf = lf_raw.filter((pl.col("date") >= pl.lit(start_date)) & (pl.col("date") <= pl.lit(end_date)))
    if WRITE_LOGS:
        logs.append(summarize_step(lf, "1_date_window", f"date in [{start_date}, {end_date}]"))

    lf = lf.unique(subset=["PERMNO", "date"], keep="first", maintain_order=False)
    if WRITE_LOGS:
        logs.append(summarize_step(lf, "2_dedup_permno_date", "unique on (PERMNO, date), keep='first'"))

    common_filter = (
        (pl.col("ShareType") == "NS")
        & (pl.col("SecurityType") == "EQTY")
        & (pl.col("SecuritySubType") == "COM")
        & (pl.col("USIncFlg") == "Y")
        & (pl.col("IssuerType").is_in(["ACOR", "CORP"]))
    )
    lf = lf.filter(common_filter).select(pl.exclude(["ShareType", "SecurityType", "USIncFlg", "SecuritySubType", "IssuerType"]))
    if WRITE_LOGS:
        logs.append(summarize_step(
            lf,
            "3_common_stock_filter",
            "ShareType='NS' & SecurityType='EQTY' & SecuritySubType='COM' & USIncFlg='Y' & IssuerType in {'ACOR','CORP'}",
        ))

    exchange_filter = (
        pl.col("PrimaryExch").is_in(["N", "A", "Q"])
        & (pl.col("ConditionalType") == "RW")
        & (pl.col("TradingStatusFlg") == "A")
    )
    lf = lf.filter(exchange_filter).select(pl.exclude(["ConditionalType", "TradingStatusFlg", "PrimaryExch"]))
    if WRITE_LOGS:
        logs.append(summarize_step(
            lf,
            "4_exchange_status_filter",
            "PrimaryExch in {'N','A','Q'} & ConditionalType='RW' & TradingStatusFlg='A'",
        ))

    tds = (
        pl.scan_csv(str(input_trading_days_csv))
        .select(pl.col("DlyCalDt").cast(pl.Date).alias("date"))
        .unique()
        .sort("date")
        .with_row_index("tdi")
        .with_columns(pl.col("tdi").cast(pl.Int64))
    )

    lf_with_tdi = lf.join(tds, on="date", how="inner")
    bounds = lf_with_tdi.group_by("PERMNO").agg(pl.col("tdi").min().alias("min_tdi"), pl.col("tdi").max().alias("max_tdi"))
    grid = (
        bounds
        .select([pl.col("PERMNO"), pl.int_ranges(pl.col("min_tdi"), pl.col("max_tdi") + 1).alias("tdi")])
        .explode("tdi")
        .join(tds, on="tdi", how="left")
    )

    lf_stage1 = (
        grid
        .join(lf_with_tdi, on=["PERMNO", "tdi"], how="left")
        .sort(["PERMNO", "tdi"])
        .select(pl.exclude(["date_right"]))
    )
    lf_stage1 = checkpoint_lazy(
        lf_stage1,
        checkpoint_dir / "stage1_filtered_panel.parquet",
        "stage1_filtered_panel",
    )
    if WRITE_LOGS:
        logs.append(summarize_step(
            lf_stage1,
            "5_add_missing_trading_days",
            "Expand each PERMNO to all CRSP trading days between its min/max observed tdi",
        ))

        attrition = pl.DataFrame(logs).select(["step", "rule", "n_rows", "n_permno", "n_trading_days", "n_permno_date_pairs"])
        attrition_with_delta = (
            attrition
            .with_columns([
                pl.col("n_rows").shift(1).alias("prev_n_rows"),
                pl.col("n_permno").shift(1).alias("prev_n_permno"),
            ])
            .with_columns([
                (pl.col("n_rows") - pl.col("prev_n_rows")).alias("delta_rows"),
                pl.when(pl.col("prev_n_rows").is_null()).then(None).otherwise((pl.col("n_rows") / pl.col("prev_n_rows") - 1.0) * 100).alias("delta_rows_pct"),
                (pl.col("n_permno") - pl.col("prev_n_permno")).alias("delta_permno"),
            ])
            .drop(["prev_n_rows", "prev_n_permno"])
        )
        stage1_status = attrition_with_delta
    else:
        stage1_status = None

    if USE_PARQUET_CHECKPOINTS:
        print(f"Stage 1 complete with parquet checkpoints in: {checkpoint_dir}")
    else:
        print("Stage 1 complete in memory; no temporary files were written.")
    if not WRITE_LOGS:
        print("WRITE_LOGS=False: skipped stage-1 diagnostic summary computations.")
    if stage1_status is not None:
        print(stage1_status)

    # Stage 2/3: momentum construction, decile assignment, enrichment.
    lf0 = (
        lf_stage1
        .select([
            pl.col("date").cast(pl.Date),
            pl.col("PERMNO").cast(pl.Int64),
            pl.col("RET").cast(pl.Float64),
            pl.col("DlyRetMissFlg").cast(pl.Utf8),
            pl.col("DlyPrevCap").cast(pl.Float64),
            pl.col("DlyCap").cast(pl.Float64),
            pl.col("PRC").cast(pl.Float64),
            pl.col("ShrOut").cast(pl.Float64),
            pl.col("DlyBid").cast(pl.Float64),
            pl.col("DlyAsk").cast(pl.Float64),
            pl.col("tdi").cast(pl.Int64),
        ])
    )

    lf_l = lf0.sort(["PERMNO", "date"]).with_columns(pl.col("RET").shift(1).over("PERMNO").alias("RET_l1"))
    calendar_t = (
        tds
        .filter((pl.col("date") >= pl.lit(start_date)) & (pl.col("date") <= pl.lit(end_date)))
        .sort("date")
        .with_columns(month=pl.col("date").dt.truncate("1mo"))
        .with_columns([
            pl.int_range(1, pl.len() + 1).over("month").sort_by("date").alias("k"),
            pl.len().over("month").alias("N"),
        ])
        .with_columns(
            (
                pl.when(pl.col("k") > (pl.col("N") - 10))
                .then(pl.col("k") - (pl.col("N") - 10))
                .otherwise(pl.col("k") + 10)
                - 10
            ).cast(pl.Int16).alias("t")
        )
        .select(["date", "t"])
    )
    lf_t = lf_l.join(calendar_t, on="date", how="left")

    variant = build_momentum_variant(lf_t, ALLOWED_FLAGS)
    lf_with_mom = variant["lf_with_mom"]
    lf_after_mom = variant["lf_after_mom"]
    lf_after_cap = variant["lf_after_cap"]
    lf_final = variant["lf_final"]
    lf_final = checkpoint_lazy(
        lf_final,
        checkpoint_dir / "stage2_momentum_daily.parquet",
        "stage2_momentum_daily",
    )

    if WRITE_LOGS:
        def summarize(lframe: pl.LazyFrame, step: str, rule: str) -> dict:
            out = collect_streaming_safe(
                lframe.select([
                    pl.len().alias("n_rows"),
                    pl.col("PERMNO").n_unique().alias("n_permno"),
                    pl.col("date").n_unique().alias("n_trading_days"),
                    pl.struct(["PERMNO", "date"]).n_unique().alias("n_permno_date_pairs"),
                    pl.struct(["PERMNO", pl.col("date").dt.truncate("1mo")]).n_unique().alias("n_permno_months"),
                ])
            ).to_dicts()[0]
            out["step"] = step
            out["rule"] = rule
            return out

        attrition = pl.DataFrame([
            summarize(lf_t, "0_input_with_t", "Loaded stage-1 panel; added RET_l1 and month-relative t"),
            summarize(lf_with_mom, "1_with_mom_code", "Joined monthly momentum to daily rows; coalesced missing mom_code to 1"),
            summarize(lf_after_mom, "2_after_mom_code_0", "Filter: mom_code == 0"),
            summarize(lf_after_cap, "3_after_DlyPrevCap_not_null", "Filter: DlyPrevCap is non-missing"),
            summarize(lf_final, "4_after_RET_not_null", "Filter: RET is non-missing"),
        ]).select(["step", "rule", "n_rows", "n_permno", "n_trading_days", "n_permno_date_pairs", "n_permno_months"])

        attrition = (
            attrition
            .with_columns([
                pl.col("n_rows").shift(1).alias("prev_rows"),
                pl.col("n_permno").shift(1).alias("prev_permno"),
            ])
            .with_columns([
                (pl.col("n_rows") - pl.col("prev_rows")).alias("delta_rows"),
                pl.when(pl.col("prev_rows").is_null()).then(None).otherwise((pl.col("n_rows") / pl.col("prev_rows") - 1.0) * 100).alias("delta_rows_pct"),
                (pl.col("n_permno") - pl.col("prev_permno")).alias("delta_permno"),
            ])
            .drop(["prev_rows", "prev_permno"])
        )

        mom_code_daily_agg = (
            lf_with_mom
            .group_by("mom_code")
            .agg([
                pl.len().alias("n_rows"),
                pl.col("PERMNO").n_unique().alias("n_permno"),
                pl.struct(["PERMNO", pl.col("date").dt.truncate("1mo")]).n_unique().alias("n_permno_months"),
            ])
        )
        mom_code_daily = (
            pl.DataFrame({"mom_code": [0, 1, 2, 3, 4, 5]})
            .with_columns(pl.col("mom_code").cast(pl.Int8))
            .lazy()
            .join(mom_code_daily_agg, on="mom_code", how="left")
            .with_columns([
                pl.col("n_rows").fill_null(0).cast(pl.Int64),
                pl.col("n_permno").fill_null(0).cast(pl.Int64),
                pl.col("n_permno_months").fill_null(0).cast(pl.Int64),
            ])
            .sort("mom_code")
            .collect()
        )
        print(mom_code_daily)

        mom_code_monthly_agg = (
            lf_with_mom
            .select(["PERMNO", "ym", "mom_code"])
            .unique()
            .group_by("mom_code")
            .agg([
                pl.len().alias("n_permno_months"),
                pl.col("PERMNO").n_unique().alias("n_permno"),
            ])
        )
        mom_code_monthly = (
            pl.DataFrame({"mom_code": [0, 1, 2, 3, 4, 5]})
            .with_columns(pl.col("mom_code").cast(pl.Int8))
            .lazy()
            .join(mom_code_monthly_agg, on="mom_code", how="left")
            .with_columns([
                pl.col("n_permno_months").fill_null(0).cast(pl.Int64),
                pl.col("n_permno").fill_null(0).cast(pl.Int64),
            ])
            .sort("mom_code")
            .collect()
        )
        print(mom_code_monthly)

        mom_summary = (
            collect_streaming_safe(
                lf_with_mom
                .select([
                    pl.when(pl.col("mom_code") == 0).then(pl.col("date")).otherwise(None).min().alias("earliest_valid_momentum_date"),
                    pl.col("date").min().alias("earliest_input_date"),
                    pl.col("date").max().alias("latest_input_date"),
                ])
            )
            .with_columns([
                pl.lit(collect_streaming_safe(lf_final.select(pl.col("date").min()))[0, 0]).cast(pl.Date).alias("earliest_final_analysis_date"),
                pl.lit(collect_streaming_safe(lf_final.select(pl.col("date").max()))[0, 0]).cast(pl.Date).alias("latest_final_analysis_date"),
                pl.lit(",".join(ALLOWED_FLAGS)).alias("allowed_flags_used"),
            ])
        )
        print(mom_summary)
    else:
        attrition = None

    bp_cols = [
        "date", "N", "q5", "q10", "q15", "q20", "q25", "q30", "q35", "q40", "q45",
        "q50", "q55", "q60", "q65", "q70", "q75", "q80", "q85", "q90", "q95", "q100",
    ]
    qcols = ["q10", "q20", "q30", "q40", "q50", "q60", "q70", "q80", "q90"]

    lf_bp = (
        pl.scan_csv(
            str(breakpoints_csv),
            has_header=False,
            skip_rows=4,
            new_columns=bp_cols,
            infer_schema_length=0,
        )
        .filter(pl.col("date").cast(pl.Utf8).str.contains(r"^[0-9]{6}$"))
        .with_columns([
            pl.col("date").cast(pl.Utf8).str.strip_chars().str.strptime(pl.Date, format="%Y%m", strict=False),
            pl.col("N").cast(pl.Utf8).str.strip_chars().cast(pl.Float64, strict=False),
            *[pl.col(c).cast(pl.Utf8).str.strip_chars().cast(pl.Float64, strict=False) / 100.0 for c in qcols],
        ])
        .select(["date", "N", *qcols])
    )

    monthly_base = lf_final.select(["PERMNO", "ym", "mom"]).unique()
    monthly_joined = (
        monthly_base
        .with_columns(pl.col("ym").dt.offset_by("-1mo").alias("date"))
        .join(lf_bp, on="date", how="left")
    )
    if WRITE_LOGS:
        monthly_joined = monthly_joined.with_columns([
            pl.col("mom").is_null().alias("mom_missing"),
            pl.col("q10").is_not_null().alias("bp_matched"),
        ])

    decile_expr = (
        pl.when(pl.col("mom").is_null()).then(None)
        .when(pl.col("q10").is_null()).then(None)
        .when(pl.col("mom") <= pl.col("q10")).then(1)
        .when(pl.col("mom") <= pl.col("q20")).then(2)
        .when(pl.col("mom") <= pl.col("q30")).then(3)
        .when(pl.col("mom") <= pl.col("q40")).then(4)
        .when(pl.col("mom") <= pl.col("q50")).then(5)
        .when(pl.col("mom") <= pl.col("q60")).then(6)
        .when(pl.col("mom") <= pl.col("q70")).then(7)
        .when(pl.col("mom") <= pl.col("q80")).then(8)
        .when(pl.col("mom") <= pl.col("q90")).then(9)
        .otherwise(10)
        .cast(pl.Int8)
        .alias("decile")
    )
    monthly_deciles = monthly_joined.with_columns([decile_expr])
    if WRITE_LOGS:
        lf_mom_deciles = monthly_deciles.select(["PERMNO", "ym", "decile", "bp_matched", "mom_missing"])
    else:
        lf_mom_deciles = monthly_deciles.select(["PERMNO", "ym", "decile"])
    lf_decile_daily = lf_final.join(lf_mom_deciles, on=["PERMNO", "ym"], how="left")

    if WRITE_LOGS:
        monthly_summary = collect_streaming_safe(monthly_deciles.select([
            pl.lit("permno_month").alias("scope"),
            pl.len().alias("valid_momentum_permno_months"),
            pl.col("bp_matched").cast(pl.Int64).sum().alias("matched_breakpoint_permno_months"),
            pl.col("decile").is_not_null().cast(pl.Int64).sum().alias("non_missing_decile_permno_months"),
            pl.col("bp_matched").not_().cast(pl.Int64).sum().alias("missing_breakpoint_permno_months"),
            pl.col("mom_missing").cast(pl.Int64).sum().alias("missing_mom_permno_months"),
        ]))
        daily_summary = collect_streaming_safe(lf_decile_daily.select([
            pl.lit("daily_rows_after_decile_merge").alias("scope"),
            pl.len().alias("valid_momentum_permno_months"),
            pl.col("bp_matched").fill_null(False).cast(pl.Int64).sum().alias("matched_breakpoint_permno_months"),
            pl.col("decile").is_not_null().cast(pl.Int64).sum().alias("non_missing_decile_permno_months"),
            pl.col("bp_matched").fill_null(False).not_().cast(pl.Int64).sum().alias("missing_breakpoint_permno_months"),
            pl.col("mom_missing").fill_null(False).cast(pl.Int64).sum().alias("missing_mom_permno_months"),
        ]))
        decile_summary = pl.concat([monthly_summary, daily_summary])
        print(decile_summary)

    lf_decile_daily = checkpoint_lazy(
        lf_decile_daily,
        checkpoint_dir / "stage3_decile_daily.parquet",
        "stage3_decile_daily",
    )

    lf_enriched = (
        lf_decile_daily
        .rename({
            "RET": "return",
            "ShrOut": "shares_outstanding",
            "DlyCap": "market_cap",
            "DlyPrevCap": "market_cap_l1",
            "PRC": "price",
            "RET_l1": "return_l1",
            "DlyBid": "bid",
            "DlyAsk": "ask",
        })
        .with_columns([
            ((pl.col("ask") - pl.col("bid")) / ((pl.col("ask") + pl.col("bid")) / 2.0)).alias("bas"),
            (pl.col("decile") == 1).cast(pl.Int8).alias("loser"),
            pl.col("t").is_between(-9, -4, closed="both").cast(pl.Int8).alias("preTOM"),
            pl.col("t").is_between(0, 3, closed="both").cast(pl.Int8).alias("TOM"),
        ])
        .with_columns([
            (pl.col("loser") * pl.col("preTOM")).alias("loser*preTOM"),
            (pl.col("market_cap") / pl.col("market_cap").sum().over(["date", "decile"])).alias("w"),
            (pl.col("market_cap_l1") / pl.col("market_cap_l1").sum().over(["date", "decile"])).alias("w_l1"),
            (pl.col("shares_outstanding") * 1000.0).alias("shares_outstanding"),
        ])
    )

    lf_factors = (
        pl.scan_csv(
            str(factors_csv),
            skip_rows=4,
            infer_schema_length=0,
            truncate_ragged_lines=True,
            ignore_errors=True,
        )
        .rename({"": "date_raw"})
        .filter(pl.col("date_raw").cast(pl.Utf8).str.contains(r"^[0-9]{8}$"))
        .with_columns([
            pl.col("date_raw").cast(pl.Utf8).str.strip_chars().str.strptime(pl.Date, format="%Y%m%d", strict=False).alias("date"),
            (pl.col("RF").cast(pl.Utf8).str.strip_chars().cast(pl.Float64, strict=False) / 100.0).alias("RF"),
            (pl.col("Mkt-RF").cast(pl.Utf8).str.strip_chars().cast(pl.Float64, strict=False) / 100.0).alias("Mkt-RF"),
            (pl.col("SMB").cast(pl.Utf8).str.strip_chars().cast(pl.Float64, strict=False) / 100.0).alias("SMB"),
            (pl.col("HML").cast(pl.Utf8).str.strip_chars().cast(pl.Float64, strict=False) / 100.0).alias("HML"),
        ])
        .with_columns((pl.col("Mkt-RF") + pl.col("RF")).alias("Mkt"))
        .select(["date", "RF", "Mkt", "SMB", "HML"])
    )

    lf_enriched = (
        lf_enriched
        .join(lf_factors, on="date", how="left")
        .with_columns(((pl.col("return") - pl.col("RF")) * 100.0 * 100.0).alias("r_e_bp"))
    )

    lf_sp500 = (
        pl.scan_csv(str(sp500_csv), infer_schema_length=100)
        .select([
            pl.col("PERMNO").cast(pl.Int64),
            pl.col("DlyCalDt").cast(pl.Date).alias("date"),
        ])
        .unique(subset=["PERMNO", "date"], keep="first")
        .with_columns(pl.lit(1, dtype=pl.Int32).alias("in_sp500"))
    )
    sp500_start_date = collect_streaming_safe(lf_sp500.select(pl.col("date").min()))[0, 0]

    lf_enriched = (
        lf_enriched
        .join(lf_sp500, on=["PERMNO", "date"], how="left")
        .with_columns(
            pl.when(pl.col("date") < pl.lit(sp500_start_date))
            .then(None)
            .otherwise(pl.col("in_sp500").fill_null(0))
            .cast(pl.Int32)
            .alias("in_sp500")
        )
    )

    drop_cols = ["mom_code", "tdi", "DlyRetMissFlg"]
    if WRITE_LOGS:
        drop_cols += ["bp_matched", "mom_missing"]
    lf_enriched = lf_enriched.drop(drop_cols)
    lf_enriched = checkpoint_lazy(
        lf_enriched,
        checkpoint_dir / "stage4_enriched_daily.parquet",
        "stage4_enriched_daily",
    )

    if WRITE_LOGS:
        enriched_summary = collect_streaming_safe(lf_enriched.select([
            pl.len().alias("rows_total"),
            pl.col("bas").is_not_null().cast(pl.Int64).sum().alias("bas_non_missing_rows"),
            (pl.col("bas").is_not_null().cast(pl.Int64).sum() / pl.len() * 100.0).alias("bas_non_missing_pct"),
            pl.col("RF").is_not_null().cast(pl.Int64).sum().alias("factors_matched_rows"),
            (pl.col("RF").is_not_null().cast(pl.Int64).sum() / pl.len() * 100.0).alias("factors_matched_pct"),
            pl.col("RF").is_null().cast(pl.Int64).sum().alias("factors_missing_rows"),
            pl.col("in_sp500").is_not_null().cast(pl.Int64).sum().alias("sp500_flag_available_rows"),
            pl.col("in_sp500").is_null().cast(pl.Int64).sum().alias("sp500_flag_missing_rows"),
            (pl.col("in_sp500") == 1).cast(pl.Int64).sum().alias("sp500_member_rows"),
            (pl.col("in_sp500") == 0).cast(pl.Int64).sum().alias("sp500_nonmember_rows"),
        ])).with_columns([
            pl.lit(sp500_start_date).cast(pl.Date).alias("sp500_first_constituent_date"),
            pl.lit(",".join(ALLOWED_FLAGS)).alias("allowed_flags_used"),
        ])
        print(enriched_summary)

    print(f"Allowed flags used: {ALLOWED_FLAGS}")
    if USE_PARQUET_CHECKPOINTS:
        print(f"Stage 2/3 complete with parquet checkpoints in: {checkpoint_dir}")
    else:
        print("Stage 2/3 complete in memory; no temporary files were written.")
    if not WRITE_LOGS:
        print("WRITE_LOGS=False: skipped stage-2/3 diagnostic summary computations.")

    # Stage 4: TAQ feature engineering and final panel merge.
    lf_panel = (
        lf_enriched
        .with_columns([
            pl.col("date").cast(pl.Date),
            pl.col("PERMNO").cast(pl.Int64),
        ])
    )

    lf_taq_raw = (
        pl.scan_parquet(str(taq_input))
        .with_columns([
            pl.col("DATE").cast(pl.Date).alias("date"),
            pl.col("PERMNO").cast(pl.Int64, strict=False),
        ])
    )

    lf_taq_features = (
        lf_taq_raw
        .filter(pl.col("PERMNO").is_not_null())
        .with_columns([
            safe_div(pl.col("SellVol_LR") - pl.col("BuyVol_LR"), pl.col("total_vol")).alias("net_sell_pressure_volume"),
            safe_div(pl.col("SellVol_LR"), pl.col("total_vol")).alias("sell_share_volume"),
            safe_div(pl.col("total_vol_Inst50k"), pl.col("total_vol")).alias("inst50k_share_volume"),
            safe_div(pl.col("SellVol_Inst50k") - pl.col("BuyVol_Inst50k"), pl.col("total_vol_Inst50k")).alias("inst50k_net_sell_pressure_volume_within"),
            safe_div(pl.col("SellVol_Inst50k") - pl.col("BuyVol_Inst50k"), pl.col("total_vol")).alias("inst50k_net_sell_pressure_volume_total"),
        ])
        .select([
            "date",
            "PERMNO",
            "net_sell_pressure_volume",
            "sell_share_volume",
            "inst50k_share_volume",
            "inst50k_net_sell_pressure_volume_within",
            "inst50k_net_sell_pressure_volume_total",
        ])
        .unique(subset=["date", "PERMNO"], keep="first")
    )
    lf_taq_features = checkpoint_lazy(
        lf_taq_features,
        checkpoint_dir / "stage5_taq_features.parquet",
        "stage5_taq_features",
    )

    lf_panel_taq = lf_panel.join(lf_taq_features, on=["date", "PERMNO"], how="left")

    if WRITE_LOGS:
        merge_summary = collect_streaming_safe(
            lf_panel_taq.select([
                pl.lit("panel_post_taq_merge").alias("scope"),
                pl.len().cast(pl.Int64).alias("rows_total"),
                pl.col("PERMNO").n_unique().cast(pl.Int64).alias("permno_total"),
                pl.col("net_sell_pressure_volume").is_not_null().cast(pl.Int64).sum().alias("rows_with_net_sell_pressure_volume"),
                pl.col("sell_share_volume").is_not_null().cast(pl.Int64).sum().alias("rows_with_sell_share_volume"),
                pl.col("inst50k_share_volume").is_not_null().cast(pl.Int64).sum().alias("rows_with_inst50k_share_volume"),
                pl.col("inst50k_net_sell_pressure_volume_within").is_not_null().cast(pl.Int64).sum().alias("rows_with_inst50k_nsp_within"),
                pl.col("inst50k_net_sell_pressure_volume_total").is_not_null().cast(pl.Int64).sum().alias("rows_with_inst50k_nsp_total"),
                (pl.col("net_sell_pressure_volume").is_not_null().cast(pl.Int64).sum() / pl.len() * 100.0).alias("pct_rows_with_net_sell_pressure_volume"),
                (pl.col("inst50k_net_sell_pressure_volume_total").is_not_null().cast(pl.Int64).sum() / pl.len() * 100.0).alias("pct_rows_with_inst50k_nsp_total"),
                pl.col("date").min().alias("panel_min_date"),
                pl.col("date").max().alias("panel_max_date"),
            ])
        ).with_columns(pl.lit(",".join(ALLOWED_FLAGS)).alias("allowed_flags_used"))

        coverage_by_year = collect_streaming_safe(
            lf_panel_taq
            .with_columns(pl.col("date").dt.year().alias("year"))
            .group_by("year")
            .agg([
                pl.len().cast(pl.Int64).alias("rows_total"),
                pl.col("PERMNO").n_unique().cast(pl.Int64).alias("permno_total"),
                pl.col("net_sell_pressure_volume").is_not_null().cast(pl.Int64).sum().alias("rows_with_net_sell_pressure_volume"),
                pl.col("inst50k_net_sell_pressure_volume_total").is_not_null().cast(pl.Int64).sum().alias("rows_with_inst50k_nsp_total"),
            ])
            .with_columns([
                (pl.col("rows_with_net_sell_pressure_volume") / pl.col("rows_total") * 100.0).alias("pct_with_net_sell_pressure_volume"),
                (pl.col("rows_with_inst50k_nsp_total") / pl.col("rows_total") * 100.0).alias("pct_with_inst50k_nsp_total"),
                pl.lit(",".join(ALLOWED_FLAGS)).alias("allowed_flags_used"),
            ])
            .sort("year")
        )
    else:
        merge_summary = None
        coverage_by_year = None

    write_lazy_parquet(lf_panel_taq, out_panel_with_taq, "final_panel_with_taq")
    if WRITE_LOGS and merge_summary is not None and coverage_by_year is not None:
        merge_summary.write_csv(str(out_taq_summary_csv))
        coverage_by_year.write_csv(str(out_taq_coverage_csv))

    print(f"Wrote final panel: {out_panel_with_taq}")
    if WRITE_LOGS:
        print(f"Wrote TAQ summary: {out_taq_summary_csv}")
        print(f"Wrote TAQ yearly coverage: {out_taq_coverage_csv}")
    else:
        print("WRITE_LOGS=False: skipped TAQ summary/coverage log exports.")


if __name__ == "__main__":
    main()

"""
_build_momentum_daily.py - Build momentum_daily.dta from CRSP parquet

Constructs daily VW and EW portfolio returns for momentum deciles 1 (losers)
and 10 (winners) using fixed monthly sorting from crsp_1927-2025_fixed_sorting_full.parquet.

This replaces the older 01_build_data.do which used Kenneth French CSVs
(daily rebalanced). The paper uses fixed monthly decile assignments.

Usage:
    python _build_momentum_daily.py [root_dir]

Output:
    data/momentum_daily.dta (~26,001 obs, 1927-2025)
"""

import sys
import os
import pyarrow.parquet as pq
import pandas as pd
import numpy as np

# Root directory
if len(sys.argv) > 1:
    root = sys.argv[1]
else:
    root = r"."

data_dir = os.path.join(root, "data")
parquet_path = os.path.join(data_dir, "crsp_1927-2025_fixed_sorting_full.parquet")
output_path = os.path.join(data_dir, "momentum_daily.dta")

print(f"Reading parquet: {parquet_path}")
cols = ['date', 'decile', 'return', 'RF', 'Mkt', 'SMB', 'HML', 't', 'w_l1']
df = pq.read_table(parquet_path, columns=cols).to_pandas()
df['date'] = pd.to_datetime(df['date'])
print(f"  Loaded {len(df):,} rows, {df['date'].nunique():,} unique dates")

# Excess return
df['ret_rf'] = df['return'] - df['RF']

# ── Value-weighted portfolio returns ──────────────────────────────────────
# VW weights: w_l1 (lagged market-cap weight within decile-date)
for dec, label in [(1, 'losers'), (10, 'winners')]:
    sub = df[df['decile'] == dec].copy()
    sub['w_norm'] = sub.groupby('date')['w_l1'].transform(lambda x: x / x.sum())
    sub['wr'] = sub['w_norm'] * sub['ret_rf']
    agg = sub.groupby('date')['wr'].sum().rename(f'{label}_vw')
    df = df.merge(agg, on='date', how='left')

# ── Equal-weighted portfolio returns ──────────────────────────────────────
for dec, label in [(1, 'losers'), (10, 'winners')]:
    sub = df[df['decile'] == dec].copy()
    agg = sub.groupby('date')['ret_rf'].mean().rename(f'{label}_ew')
    df = df.merge(agg, on='date', how='left')

# ── Collapse to one row per date ──────────────────────────────────────────
daily = df.groupby('date').agg(
    t=('t', 'first'),
    losers_vw=('losers_vw', 'first'),
    winners_vw=('winners_vw', 'first'),
    losers_ew=('losers_ew', 'first'),
    winners_ew=('winners_ew', 'first'),
    mktrf=('Mkt', 'first'),
    smb=('SMB', 'first'),
    hml=('HML', 'first'),
    rf=('RF', 'first'),
).reset_index()

# WML
daily['wml_vw'] = daily['winners_vw'] - daily['losers_vw']
daily['wml_ew'] = daily['winners_ew'] - daily['losers_ew']

# Year-month
daily['ym'] = daily['date'].dt.to_period('M').apply(lambda x: (x.year - 1960) * 12 + x.month - 1)

# Convert smb/hml from percentage to decimal if needed
# Check scale: if smb values are > 1 on average, they're in percentage points
if daily['smb'].abs().mean() > 0.5:
    daily['smb'] = daily['smb'] / 100
    daily['hml'] = daily['hml'] / 100

# Ensure date is datetime for pandas to_stata conversion.
# We pass convert_dates={'date': 'td'} to write as Stata %td format
# (days since 1960-01-01) so that year(date), mofd(date), etc. work correctly.
# Without this, pandas writes datetime64 as Stata %tc (milliseconds), which
# causes year(date) to return missing in Stata.

# Order columns to match existing dta
daily = daily[['date', 'ym', 't', 'winners_vw', 'losers_vw', 'wml_vw',
               'winners_ew', 'losers_ew', 'wml_ew', 'mktrf', 'smb', 'hml', 'rf']]

daily = daily.sort_values('date').reset_index(drop=True)

print(f"  Output: {len(daily):,} obs, {daily['date'].min().date()} to {daily['date'].max().date()}")
print(f"  t range: {daily['t'].min()} to {daily['t'].max()}")

# Sanity checks
n1980 = len(daily[daily['date'].dt.year >= 1980])
print(f"  1980+ obs: {n1980:,}")

# Save as Stata
daily.to_stata(output_path, write_index=False,
               convert_dates={'date': 'td'},
               variable_labels={
                   'date': 'Trading date',
                   'ym': 'Year-month (Stata monthly)',
                   't': 'Trading day relative to month-end (0=last day)',
                   'winners_vw': 'Winner decile excess return (VW)',
                   'losers_vw': 'Loser decile excess return (VW)',
                   'wml_vw': 'WML = Winners - Losers (VW)',
                   'winners_ew': 'Winner decile excess return (EW)',
                   'losers_ew': 'Loser decile excess return (EW)',
                   'wml_ew': 'WML = Winners - Losers (EW)',
                   'mktrf': 'Market excess return',
                   'smb': 'SMB factor',
                   'hml': 'HML factor',
                   'rf': 'Risk-free rate',
               })
print(f"  Saved: {output_path}")

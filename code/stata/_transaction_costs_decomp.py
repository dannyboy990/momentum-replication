"""
Transaction cost decomposition of monthly momentum returns.

Strategy: standard VW WML (long decile 10, short decile 1), rebalanced monthly.
Decompose monthly return into PreTOM [t-9,t-4] vs Rest-of-month components.

Transaction cost methodology (following Novy-Marx and Velikov, 2016, RFS):
  - Cost measure: quoted bid-ask spread from CRSP, (ask - bid) / midpoint.
    This is a round-trip cost. NMV use the Hasbrouck (2009) effective spread,
    which is typically smaller; our quoted-spread estimate is conservative.
  - Turnover: a stock "turns over" if it changes momentum decile or is new
    to the sample. Stocks remaining in the same decile incur zero cost.
  - Cost per side per month:
      TC_side = sum_i [ w_i * BAS_i * trade_i ]
    where w_i is VW weight, BAS_i is the stock's monthly average quoted spread,
    and trade_i = 1 if the stock entered the decile this month.
  - This charges one full round-trip spread per entrant. Since entry rate ≈
    exit rate (verified: both ~21% for losers, ~26% for winners), charging
    full BAS to entrants approximates half-spread to entrants + half-spread
    to exiters (whose BAS is similar).
  - Total TC = loser_tc + winner_tc (both sides of the long-short).

Input:  data/panel_full_march4v7.parquet
Output: printed table (manually transferred to LaTeX)
"""

import pyarrow.parquet as pq
import pandas as pd
import numpy as np

ROOT = "C:/Users/danie/Dropbox/Timing Momentum"

print("Loading parquet...")
cols = ['date','PERMNO','decile','return','market_cap_l1','bas','t']
pf = pq.read_table(f'{ROOT}/data/panel_full_march4v7.parquet', columns=cols).to_pandas()
pf = pf[pf['date'].dt.year >= 1980].copy()
pf = pf.dropna(subset=['decile','market_cap_l1','return'])
pf['ym'] = pf['date'].dt.to_period('M')
pf['year'] = pf['date'].dt.year

# ── Trade indicator ──────────────────────────────────────────────────────────
# trade_i = 1 if stock changed decile or is new to the sample this month
mem = pf.groupby(['PERMNO','ym'])['decile'].first().reset_index()
mem = mem.sort_values(['PERMNO','ym'])
mem['dec_lag'] = mem.groupby('PERMNO')['decile'].shift(1)
mem['ym_lag'] = mem.groupby('PERMNO')['ym'].shift(1)
mem['trade'] = ((mem['decile'] != mem['dec_lag']) | mem['dec_lag'].isna()).astype(int)
# Also flag gaps (stock absent last month = new entry)
ym_ord = mem['ym'].apply(lambda x: x.ordinal)
ym_lag_ord = mem['ym_lag'].apply(lambda x: x.ordinal if pd.notna(x) else -999)
mem.loc[(ym_ord - ym_lag_ord) != 1, 'trade'] = 1
pf = pf.merge(mem[['PERMNO','ym','trade']], on=['PERMNO','ym'], how='left')

# ── Monthly stock-level BAS ──────────────────────────────────────────────────
# Average daily quoted spread within the month, excluding invalid observations
bas_valid = pf[pf['bas'].notna() & (pf['bas'] > 0)]
bas_mo = bas_valid.groupby(['PERMNO','ym'])['bas'].mean().reset_index()
bas_mo.columns = ['PERMNO','ym','bas_mo']
pf = pf.merge(bas_mo, on=['PERMNO','ym'], how='left')

# ── Window indicator ─────────────────────────────────────────────────────────
pf['pretom'] = ((pf['t'] >= -9) & (pf['t'] <= -4)).astype(int)

print(f"Obs: {len(pf):,}")


def decompose(pf_sub):
    """Decompose monthly VW WML into PreTOM, Rest, and transaction costs."""
    dat = pf_sub.copy()

    monthly_pieces = []
    for dec, dl in [(1, 'loser'), (10, 'winner')]:
        dsub = dat[dat['decile'] == dec].copy()

        # VW daily returns for PreTOM and Rest separately, compounded to monthly
        for window_label, window_val in [('pretom', 1), ('rest', 0)]:
            wsub = dsub[dsub['pretom'] == window_val]
            daily = wsub.groupby(['ym','date']).apply(
                lambda x: np.average(x['return'], weights=x['market_cap_l1']),
                include_groups=False
            ).reset_index(name='ret')
            daily['ret_1p'] = 1 + daily['ret']
            mret = daily.groupby('ym')['ret_1p'].prod().reset_index()
            mret.columns = ['ym', f'{dl}_{window_label}_1p']
            mret[f'{dl}_{window_label}_bps'] = (mret[f'{dl}_{window_label}_1p'] - 1) * 10000
            monthly_pieces.append(mret[['ym', f'{dl}_{window_label}_bps']])

        # Full month return (compound all days)
        daily_full = dsub.groupby(['ym','date']).apply(
            lambda x: np.average(x['return'], weights=x['market_cap_l1']),
            include_groups=False
        ).reset_index(name='ret')
        daily_full['ret_1p'] = 1 + daily_full['ret']
        mret_full = daily_full.groupby('ym')['ret_1p'].prod().reset_index()
        mret_full.columns = ['ym', f'{dl}_full_1p']
        mret_full[f'{dl}_full_bps'] = (mret_full[f'{dl}_full_1p'] - 1) * 10000
        monthly_pieces.append(mret_full[['ym', f'{dl}_full_bps']])

        # Monthly TC: VW average of (BAS * trade_indicator)
        # One observation per stock-month (first day)
        first = dsub.groupby(['PERMNO','ym']).first().reset_index()
        first = first[first['bas_mo'].notna()]
        first['tc_stock'] = first['bas_mo'] * first['trade']
        mtc = first.groupby('ym').apply(
            lambda g: np.average(g['tc_stock'], weights=g['market_cap_l1']) * 10000,
            include_groups=False
        ).reset_index(name=f'{dl}_tc')
        monthly_pieces.append(mtc)

    # Merge everything on ym
    result = monthly_pieces[0]
    for p in monthly_pieces[1:]:
        result = result.merge(p, on='ym', how='outer')

    # WML components
    result['wml_pretom'] = result['winner_pretom_bps'] - result['loser_pretom_bps']
    result['wml_rest'] = result['winner_rest_bps'] - result['loser_rest_bps']
    result['wml_full'] = result['winner_full_bps'] - result['loser_full_bps']
    result['tc'] = result['loser_tc'] + result['winner_tc']
    result['wml_net'] = result['wml_full'] - result['tc']

    return result


for period_label, yr_min, yr_max in [
    ('FULL SAMPLE (1980-2025)', 1980, 2025),
    ('POST-DECIMALIZATION (2001-2025)', 2001, 2025),
]:
    print(f"\n{'='*70}")
    print(period_label)
    print('='*70)

    pf_period = pf[(pf['year'] >= yr_min) & (pf['year'] <= yr_max)]
    m = decompose(pf_period)
    n = len(m)

    g_full = m['wml_full'].mean()
    g_pretom = m['wml_pretom'].mean()
    g_rest = m['wml_rest'].mean()
    tc = m['tc'].mean()
    net = m['wml_net'].mean()

    gs = m['wml_full'].std()
    ns = m['wml_net'].std()
    gt = g_full / (gs / np.sqrt(n))
    nt = net / (ns / np.sqrt(n))
    pt = g_pretom / (m['wml_pretom'].std() / np.sqrt(n))
    rt = g_rest / (m['wml_rest'].std() / np.sqrt(n))

    pct_pretom = g_pretom / g_full * 100 if g_full != 0 else float('nan')

    print(f"\n  n = {n} months")
    print(f"  Gross WML (full month): {g_full:+.1f} bps/mo (t={gt:.2f})")
    print(f"    PreTOM component:     {g_pretom:+.1f} bps/mo (t={pt:.2f})  [{pct_pretom:.0f}% of gross]")
    print(f"    Rest component:       {g_rest:+.1f} bps/mo (t={rt:.2f})  [{100-pct_pretom:.0f}% of gross]")
    print(f"  TC (round-trip BAS):    {tc:.1f} bps/mo")
    print(f"  Net WML:                {net:+.1f} bps/mo (t={nt:.2f})")
    print(f"  Sharpe (ann.): gross={g_full/gs*np.sqrt(12):.2f}, net={net/ns*np.sqrt(12):.2f}")

print("\nDone.")

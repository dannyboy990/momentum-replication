"""
JT Holding Period Decomposition: Market-Adjusted, Newey-West SEs
----------------------------------------------------------------
French 12-2 deciles, K=1,3,6,9,12 holding periods.
Loser-Mkt, Winner-Mkt, WML decomposed into PreTOM vs rest.
NW(K-1) lags for overlapping portfolio autocorrelation.
"""

import pandas as pd
import pyarrow.parquet as pq
import numpy as np
import warnings
warnings.filterwarnings('ignore')

DATA = "C:/Users/dnatha/Dropbox/Timing Momentum/data"

def newey_west_se(x, max_lag):
    """Newey-West SE for the mean of a series x with max_lag lags."""
    x = x.values if hasattr(x, 'values') else np.array(x)
    x = x[~np.isnan(x)]
    n = len(x)
    if n < 2:
        return np.nan
    xbar = x.mean()
    e = x - xbar

    # Gamma_0
    gamma0 = np.dot(e, e) / n

    # Add autocovariance terms with Bartlett weights
    nw_var = gamma0
    for lag in range(1, max_lag + 1):
        weight = 1 - lag / (max_lag + 1)
        gamma_j = np.dot(e[lag:], e[:-lag]) / n
        nw_var += 2 * weight * gamma_j

    return np.sqrt(nw_var / n)


# ── 1. Load data ──────────────────────────────────────────────────────────
print("Loading parquet...")
cols = ['date', 'PERMNO', 'decile', 'return', 'market_cap_l1', 't', 'preTOM', 'Mkt', 'RF']
df = pq.read_table(f"{DATA}/crsp_1927-2025_fixed_sorting_full.parquet", columns=cols).to_pandas()
df['date'] = pd.to_datetime(df['date'])
df['ym'] = df['date'].dt.to_period('M')
df = df[df['date'] >= '1980-01-01'].copy()
df = df.dropna(subset=['decile', 'return', 'market_cap_l1'])
df = df[df['market_cap_l1'] > 0]
print(f"  {len(df):,} rows")

# Decile lookup
decile_lookup = df.groupby(['PERMNO', 'ym'])['decile'].first().reset_index()
all_ym = sorted(df['ym'].unique())
ym_to_idx = {ym: i for i, ym in enumerate(all_ym)}
idx_to_ym = {i: ym for ym, i in ym_to_idx.items()}
decile_lookup['ym_idx'] = decile_lookup['ym'].map(ym_to_idx)

date_info = df.groupby('date')[['t', 'preTOM', 'Mkt', 'RF']].first()
date_info['mkt_raw'] = date_info['Mkt'] + date_info['RF']

daily = df[['date', 'PERMNO', 'ym', 'return', 'market_cap_l1']].copy()

# ── 2. VW returns by vintage ─────────────────────────────────────────────
MAX_K = 12

def compute_vw_returns_for_vintage(daily_data, decile_lookup, lag_months):
    lookup = decile_lookup[['PERMNO', 'ym_idx', 'decile']].copy()
    lookup['ym_idx'] = lookup['ym_idx'] + lag_months
    lookup = lookup[lookup['ym_idx'].isin(idx_to_ym)]
    lookup['ym'] = lookup['ym_idx'].map(idx_to_ym)
    lookup = lookup[['PERMNO', 'ym', 'decile']]
    merged = daily_data.merge(lookup, on=['PERMNO', 'ym'], how='inner')

    def vw_ret(grp):
        w = grp['market_cap_l1'].values
        r = grp['return'].values
        tw = w.sum()
        if tw <= 0:
            return np.nan
        return np.dot(w, r) / tw

    w_ret = merged[merged['decile'] == 10].groupby('date').apply(vw_ret)
    l_ret = merged[merged['decile'] == 1].groupby('date').apply(vw_ret)
    return pd.DataFrame({'winner': w_ret, 'loser': l_ret})

print("Computing VW returns by vintage...")
vintage_rets = {}
for j in range(MAX_K):
    print(f"  Vintage {j}...", end="")
    vintage_rets[j] = compute_vw_returns_for_vintage(daily, decile_lookup, j)
    print(f" done")

# ── 3. Construct overlapping portfolios & decompose ──────────────────────
K_values = [1, 3, 6, 9, 12]
results = []

for K in K_values:
    nw_lags = max(K - 1, 0)  # NW(K-1) for overlapping portfolios

    w_frames = [vintage_rets[j]['winner'].rename(f'w{j}') for j in range(K)]
    l_frames = [vintage_rets[j]['loser'].rename(f'l{j}') for j in range(K)]

    port = pd.DataFrame({
        'winner': pd.concat(w_frames, axis=1).mean(axis=1),
        'loser': pd.concat(l_frames, axis=1).mean(axis=1),
    })
    port = port.join(date_info)
    port['wml'] = port['winner'] - port['loser']
    port['winner_mktadj'] = port['winner'] - port['mkt_raw']
    port['loser_mktadj'] = port['loser'] - port['mkt_raw']

    valid = port.dropna(subset=['wml', 'preTOM', 'mkt_raw']).copy()
    valid['ym'] = valid.index.to_period('M')

    for series_name, col in [('Loser-Mkt', 'loser_mktadj'),
                              ('Winner-Mkt', 'winner_mktadj'),
                              ('WML', 'wml')]:
        pretom_monthly = valid[valid['preTOM'] == 1].groupby('ym')[col].apply(
            lambda x: (1 + x).prod() - 1)
        rest_monthly = valid[valid['preTOM'] == 0].groupby('ym')[col].apply(
            lambda x: (1 + x).prod() - 1)
        total_monthly = valid.groupby('ym')[col].apply(
            lambda x: (1 + x).prod() - 1)

        # Newey-West SEs
        pm = pretom_monthly.mean() * 10000
        rm = rest_monthly.mean() * 10000
        tm = total_monthly.mean() * 10000

        pse_nw = newey_west_se(pretom_monthly * 10000, nw_lags)
        rse_nw = newey_west_se(rest_monthly * 10000, nw_lags)
        tse_nw = newey_west_se(total_monthly * 10000, nw_lags)

        # Also plain SEs for comparison
        pse = pretom_monthly.std() / np.sqrt(len(pretom_monthly)) * 10000
        rse = rest_monthly.std() / np.sqrt(len(rest_monthly)) * 10000
        tse = total_monthly.std() / np.sqrt(len(total_monthly)) * 10000

        wp = (1 + pretom_monthly).prod()
        wr = (1 + rest_monthly).prod()

        results.append({
            'K': K, 'series': series_name, 'nw_lags': nw_lags,
            'pretom_bps': pm, 'rest_bps': rm, 'total_bps': tm,
            'pretom_t_nw': pm / pse_nw if pse_nw > 0 else 0,
            'rest_t_nw': rm / rse_nw if rse_nw > 0 else 0,
            'total_t_nw': tm / tse_nw if tse_nw > 0 else 0,
            'pretom_t_plain': pm / pse if pse > 0 else 0,
            'rest_t_plain': rm / rse if rse > 0 else 0,
            'total_t_plain': tm / tse if tse > 0 else 0,
            'wealth_pretom': wp, 'wealth_rest': wr,
        })

# ── 4. Print results ────────────────────────────────────────────────────
def s(t):
    a = abs(t)
    return '***' if a > 2.58 else '**' if a > 1.96 else '*' if a > 1.65 else ''

print(f"\n{'='*90}")
print("MARKET-ADJUSTED DECOMPOSITION BY HOLDING PERIOD")
print("French 12-2 deciles, VW, 1980-2025. Newey-West(K-1) t-stats.")
print(f"{'='*90}")

for series in ['Loser-Mkt', 'Winner-Mkt', 'WML']:
    print(f"\n  {series}")
    print(f"  {'K':>3} {'NW':>4} {'PreTOM':>9} {'(t)':>8} {'Rest':>9} {'(t)':>8} {'Total':>9} {'(t)':>8} {'$Pre':>8} {'$Rest':>8}")
    print("  " + "-" * 80)
    for K in K_values:
        r = [x for x in results if x['K'] == K and x['series'] == series][0]
        ps = s(r['pretom_t_nw'])
        rs = s(r['rest_t_nw'])
        ts = s(r['total_t_nw'])
        print(f"  {K:>3} {r['nw_lags']:>4} "
              f"{r['pretom_bps']:>8.1f}{ps} ({r['pretom_t_nw']:>5.2f})  "
              f"{r['rest_bps']:>8.1f}{rs} ({r['rest_t_nw']:>5.2f})  "
              f"{r['total_bps']:>8.1f}{ts} ({r['total_t_nw']:>5.2f})  "
              f"${r['wealth_pretom']:>6.2f} ${r['wealth_rest']:>6.2f}")

# Compact with both plain and NW t-stats
print(f"\n{'='*90}")
print("t-STAT COMPARISON: Plain vs Newey-West(K-1)")
print(f"{'='*90}")
for series in ['Loser-Mkt', 'Winner-Mkt', 'WML']:
    print(f"\n  {series}")
    print(f"  {'K':>3} {'NW':>4} | {'PreTOM':>8} {'t_plain':>8} {'t_NW':>8} | {'Rest':>8} {'t_plain':>8} {'t_NW':>8} | {'Total':>8} {'t_plain':>8} {'t_NW':>8}")
    print("  " + "-" * 90)
    for K in K_values:
        r = [x for x in results if x['K'] == K and x['series'] == series][0]
        print(f"  {K:>3} {r['nw_lags']:>4} | "
              f"{r['pretom_bps']:>8.1f} {r['pretom_t_plain']:>7.2f} {r['pretom_t_nw']:>7.2f}{s(r['pretom_t_nw'])} | "
              f"{r['rest_bps']:>8.1f} {r['rest_t_plain']:>7.2f} {r['rest_t_nw']:>7.2f}{s(r['rest_t_nw'])} | "
              f"{r['total_bps']:>8.1f} {r['total_t_plain']:>7.2f} {r['total_t_nw']:>7.2f}{s(r['total_t_nw'])}")

print("\nDone.")

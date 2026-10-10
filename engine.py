"""Pure logic (no Streamlit): investor profile validation, finance metrics, recommender. Unit-tested in tests/."""
from __future__ import annotations
import math, re
import numpy as np, pandas as pd

SECTORS = {'Bajaj Auto': 'Auto', 'Eicher Motors': 'Auto', 'Hero Motocorp': 'Auto', 'TVS Motors': 'Auto', 'Infosys': 'IT', 'TCS': 'IT'}
# factor weights per goal: rr = risk-adjusted return, dd = drawdown fit, trend = MA20/50 trend, vol = volatility fit, sector = preference
GOALS = {'growth': dict(rr=.40, dd=.15, trend=.25, vol=.10, sector=.10),
         'balanced': dict(rr=.30, dd=.25, trend=.15, vol=.20, sector=.10),
         'preservation': dict(rr=.20, dd=.35, trend=.10, vol=.25, sector=.10)}
TARGET_VOL = {1: 15, 2: 18, 3: 22, 4: 27, 5: 32}  # annual volatility (%) matched to risk tolerance 1-5
DEFAULT = dict(name='', age=25, capital=100000, horizon_years=3, goal='balanced', risk_tolerance=3,
               max_drawdown_pct=25, sector_pref='Any', n_stocks=3, risk_free_pct=6.0)

INPUTS = ("**Profile:** goal, risk tolerance (1-5), max drawdown you accept, sector preference, capital, number of stocks.  \n"
          "**Market data (from SQL):** return per unit of risk, annual volatility, max drawdown, current MA 20/50 trend, return correlations.")
LOGIC = ("1. Each stock gets five factor scores (0-1): risk-adjusted return, drawdown fit, volatility fit, trend, sector.  \n"
         "2. Score = 100 x weighted sum; weights depend on your goal.  \n"
         "3. Stocks are picked greedily; a pick correlated above 0.3 with one already chosen is penalised (diversification).  \n"
         "4. Allocation is proportional to score, capped at 50% per stock.")
OUTPUT = "A ranked table with score, allocation % and rupee amount per stock, plus the reason each was chosen. It is a screening aid, not a prediction."

def validate_profile(p: dict) -> list[str]:
    e = []
    def rng(k, lo, hi):
        v = p.get(k)
        if not isinstance(v, (int, float)) or isinstance(v, bool) or not lo <= v <= hi: e.append(f'{k} must be between {lo} and {hi}')
    rng('age', 18, 100); rng('capital', 10_000, 10**9); rng('horizon_years', 1, 30); rng('risk_tolerance', 1, 5)
    rng('max_drawdown_pct', 5, 60); rng('n_stocks', 2, 6); rng('risk_free_pct', 0, 15)
    if p.get('goal') not in GOALS: e.append(f'goal must be one of {list(GOALS)}')
    if p.get('sector_pref') not in ('Any', 'Auto', 'IT'): e.append('sector_pref must be Any, Auto or IT')
    return e

def cagr(first: float, last: float, days: int) -> float:
    return (last / first) ** (365 / days) - 1 if first > 0 and last > 0 and days > 0 else float('nan')
def ann_vol(r) -> float: return float(np.std(np.asarray(r, float), ddof=1) * math.sqrt(252))
def sharpe(c: float, vol: float, rf: float = 0.06) -> float: return (c - rf) / vol if vol > 0 else float('nan')
def max_drawdown(prices) -> float:
    s = pd.Series(prices, dtype=float); return float((s / s.cummax() - 1).min())
def var95(r) -> float: return float(-np.percentile(np.asarray(r, float), 5))  # historical 1-day 95% VaR (fraction)
def position_size(capital: float, risk_pct: float, stop_pct: float) -> float:
    """Capital to deploy so that hitting the stop loses only risk_pct of capital."""
    return min(capital, capital * risk_pct / stop_pct) if stop_pct > 0 else 0.0

def portfolio_curve(prices: pd.DataFrame, alloc: dict, start: str) -> pd.Series:
    x = prices.loc[prices.index >= start, list(alloc)]
    if x.empty: raise ValueError('no prices on or after the start date')
    return sum(amt * x[s] / x[s].iloc[0] for s, amt in alloc.items())

def _mm(s: pd.Series) -> pd.Series:
    r = s.max() - s.min(); return (s - s.min()) / r if r else s * 0 + .5

def recommend(profile: dict, m: pd.DataFrame, corr: pd.DataFrame | None = None) -> pd.DataFrame:
    """m: stock, return_per_risk, ann_vol_pct, max_drawdown_pct (negative), trend (1/0)."""
    err = validate_profile(profile)
    if err: raise ValueError('; '.join(err))
    w, d, tol = GOALS[profile['goal']], m.copy(), profile['max_drawdown_pct']
    d['trend'] = d['trend'].fillna(0); tv = TARGET_VOL[int(profile['risk_tolerance'])]
    d['sector'] = d['stock'].map(SECTORS)
    f = pd.DataFrame({'rr': _mm(d['return_per_risk']),
                      'dd': (1 - (d['max_drawdown_pct'].abs() - tol) / tol).clip(0, 1),
                      'vol': (1 - (d['ann_vol_pct'] - tv).abs() / tv).clip(0, 1),
                      'trend': d['trend'].astype(float),
                      'sector': d['sector'].map(lambda s: 1.0 if profile['sector_pref'] in ('Any', s) else 0.0)})
    d['score'] = 100 * sum(w[k] * f[k] for k in w); fs = f.set_index(d['stock'])
    chosen, rows = [], d.set_index('stock')
    while len(chosen) < min(profile['n_stocks'], len(d)):
        adj = rows['score'].copy()
        if corr is not None and chosen:
            for s in [x for x in adj.index if x not in chosen]: adj[s] -= 40 * max(0, max(corr.loc[s, c] for c in chosen) - .3)
        adj = adj.drop(chosen); chosen.append(adj.idxmax()); rows.loc[chosen[-1], 'adj'] = adj.max()
    sel = rows.loc[chosen].copy(); sel['adj'] = sel['adj'].clip(lower=1)
    wt = sel['adj'] / sel['adj'].sum()
    for _ in range(5): wt = (wt.clip(upper=.5) / wt.clip(upper=.5).sum())
    out = pd.DataFrame({'stock': sel.index, 'sector': sel['sector'].values, 'score': sel['score'].round(1).values,
                        'allocation_pct': (100 * wt).round(1).values})
    out['amount_inr'] = (profile['capital'] * out['allocation_pct'] / 100).round(0)
    lab = dict(rr='risk-adjusted return', dd='drawdown within your limit', vol='volatility fits your risk level', trend='uptrend (MA20 > MA50)', sector='sector match')
    out['why'] = [', '.join(lab[k] for k in sorted(w, key=lambda k: -w[k] * fs.loc[s, k])[:2] if fs.loc[s, k] > .5) or 'diversifier' for s in sel.index]
    return out.reset_index(drop=True)

_BLOCKED = re.compile(r'\b(ATTACH|DETACH|PRAGMA|VACUUM|LOAD_EXTENSION)\b', re.I)

def run_sandbox(con, sql: str):
    """Run one or more statements on a per-session sandbox DB. Returns (last SELECT result or None, statements run)."""
    sql = '\n'.join(l for l in sql.split('\n') if not l.strip().startswith('--'))
    if _BLOCKED.search(sql): raise ValueError('ATTACH / PRAGMA / VACUUM are not allowed in the playground')
    df, n = None, 0
    for q in [x.strip() for x in sql.split(';') if x.strip()]:
        if re.match(r'(DELIMITER|DROP FUNCTION|CREATE FUNCTION)', q, re.I): raise ValueError('Functions and DELIMITER are MySQL-only: run Task 9 in MySQL Workbench')
        m = re.match(r'CREATE OR REPLACE VIEW (\w+)', q, re.I)
        if m: con.execute(f'DROP VIEW IF EXISTS {m.group(1)}'); q = re.sub(r'(?i)CREATE OR REPLACE VIEW', 'CREATE VIEW', q, count=1)
        if re.match(r'(SELECT|WITH)\b', q, re.I): df = pd.read_sql(q, con)
        else: con.execute(q)
        n += 1
    con.commit(); return df, n

def metrics_asof(pw: pd.DataFrame, i: int):
    """Recommender inputs using ONLY prices up to row i (no look-ahead)."""
    h = pw.iloc[:i + 1]; r = h.pct_change().dropna(); days = (pd.Timestamp(h.index[-1]) - pd.Timestamp(h.index[0])).days
    vol = r.std() * math.sqrt(252); cg = (h.iloc[-1] / h.iloc[0]) ** (365 / days) - 1
    m = pd.DataFrame({'stock': h.columns, 'return_per_risk': (cg / vol).values, 'ann_vol_pct': (100 * vol).values,
                      'max_drawdown_pct': (100 * (h / h.cummax() - 1).min()).values,
                      'trend': (h.rolling(20).mean().iloc[-1] > h.rolling(50).mean().iloc[-1]).astype(int).values})
    return m, r.corr()

def walk_forward(pw: pd.DataFrame, profile: dict, start: int = 252, step: int = 63, cost: float = 0.001):
    """Re-run the recommender every `step` sessions using only past data; hold until the next rebalance."""
    dates, i = list(pw.index), start; idx, eq, bench, picks = [dates[start]], [1.0], [1.0], []
    while i < len(dates) - 1:
        m, c = metrics_asof(pw, i); w = recommend(profile, m, c).set_index('stock')['allocation_pct'] / 100
        j = min(i + step, len(dates) - 1); seg = pw.iloc[i:j + 1] / pw.iloc[i]
        eq += list(eq[-1] * (1 - cost) * (seg[w.index] * w).sum(axis=1).iloc[1:]); bench += list(bench[-1] * seg.mean(axis=1).iloc[1:])
        idx += dates[i + 1:j + 1]; picks.append((dates[i], ', '.join(w.index))); i = j
    return pd.DataFrame({'Recommender (past data only)': eq, 'Equal-weight, all six': bench}, index=idx), picks
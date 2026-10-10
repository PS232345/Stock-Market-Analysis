import pandas as pd, pytest
from engine import *

M = pd.DataFrame({'stock': ['TCS', 'Infosys', 'Bajaj Auto', 'TVS Motors'], 'return_per_risk': [.58, .40, .12, .62],
                  'ann_vol_pct': [21.6, 23.8, 23.3, 30.8], 'max_drawdown_pct': [-24.1, -31.1, -23.2, -34.6], 'trend': [0, 1, 1, 0]})
def test_validate_ok(): assert validate_profile(DEFAULT) == []
def test_validate_bad():
    assert len(validate_profile({**DEFAULT, 'age': 10, 'goal': 'x', 'risk_tolerance': 9})) == 3
def test_cagr(): assert cagr(100, 121, 730) == pytest.approx(.1, abs=.01)
def test_max_drawdown(): assert max_drawdown([100, 120, 90, 130]) == pytest.approx(-.25)
def test_position_size(): assert position_size(100000, 1, 5) == 20000 and position_size(1000, 5, 1) == 1000
def test_recommend_weights():
    r = recommend({**DEFAULT, 'n_stocks': 3}, M)
    assert len(r) == 3 and r.allocation_pct.sum() == pytest.approx(100, abs=.3) and (r.allocation_pct <= 50.1).all()
def test_sector_pref():
    r = recommend({**DEFAULT, 'sector_pref': 'IT', 'n_stocks': 2}, M); assert set(r.stock) == {'TCS', 'Infosys'}
def test_low_risk_avoids_high_vol():
    assert 'TVS Motors' not in set(recommend({**DEFAULT, 'risk_tolerance': 1, 'max_drawdown_pct': 20, 'n_stocks': 2}, M).stock)
def test_invalid_raises():
    with pytest.raises(ValueError): recommend({**DEFAULT, 'capital': 5}, M)
def test_curve():
    p = pd.DataFrame({'A': [10, 20]}, index=['2020-01-01', '2020-01-02']); assert portfolio_curve(p, {'A': 100}, '2020-01-01').iloc[-1] == 200
def test_correlation_penalty():
    C = pd.DataFrame(.1, index=M.stock, columns=M.stock); C.loc['TCS', 'Infosys'] = C.loc['Infosys', 'TCS'] = .9
    for s in M.stock: C.loc[s, s] = 1
    assert len(recommend({**DEFAULT, 'n_stocks': 3}, M, C)) == 3
def test_sandbox():
    import sqlite3
    c = sqlite3.connect(':memory:'); c.execute('CREATE TABLE a(x)'); c.execute('INSERT INTO a VALUES (1),(2)')
    df, n = run_sandbox(c, '-- c\nDROP TABLE IF EXISTS b; CREATE TABLE b AS SELECT x*2 AS y FROM a; SELECT SUM(y) AS s FROM b;')
    assert n == 3 and df.s[0] == 6
    with pytest.raises(ValueError): run_sandbox(c, 'PRAGMA table_info(a)')
    with pytest.raises(ValueError): run_sandbox(c, 'DELIMITER $$')
def test_walk_forward_no_lookahead():
    import numpy as np
    idx = pd.date_range('2020-01-01', periods=400, freq='B').strftime('%Y-%m-%d')
    pw = pd.DataFrame({s: 100 * np.cumprod(1 + np.random.default_rng(n).normal(.0004, .01, 400)) for n, s in enumerate(M.stock)}, index=idx)
    r, picks = walk_forward(pw, {**DEFAULT, 'n_stocks': 2}, start=100, step=50)
    assert len(r) > 200 and r.iloc[0, 0] == 1.0 and len(picks) >= 5

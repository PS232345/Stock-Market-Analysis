"""NSE Stock Analysis in SQL: Streamlit dashboard.  Run: streamlit run app.py
Needs ./data/*.csv (six files) and stock_advanced_analysis.sql next to this file.
Every result below is produced by the SQL shown in its 'Show SQL' expander (MySQL syntax in the file;
the app runs it on an in-memory SQLite copy through small compatibility shims)."""
import re, math, sqlite3, datetime, pathlib
import json
import pandas as pd, altair as alt, streamlit as st
from engine import (run_sandbox, walk_forward, DEFAULT, GOALS, validate_profile, recommend, cagr, ann_vol, sharpe, max_drawdown,
                    var95, position_size, portfolio_curve, INPUTS, LOGIC, OUTPUT)

BASE = pathlib.Path(__file__).parent
COLS = ['date','open_price','high_price','low_price','close_price','wap','no_of_shares','no_of_trades',
        'total_turnover','deliverable_qty','pct_deli_qty','spread_high_low','spread_close_open']
FILES = {'Bajaj_Auto':('bajaj_auto','Bajaj Auto'),'Eicher_Motors':('eicher_motors','Eicher Motors'),
         'Hero_Motocorp':('hero_motocorp','Hero Motocorp'),'Infosys':('infosys','Infosys'),
         'TCS':('tcs','TCS'),'TVS_Motors':('tvs_motors','TVS Motors')}
NAMES = [v[1] for v in FILES.values()]

class _SD:  # STDDEV_SAMP as aggregate + window function
    def __init__(s): s.v = []
    def step(s, x):
        if x is not None: s.v.append(x)
    def inverse(s, x):
        if x is not None: s.v.remove(x)
    def value(s):
        n = len(s.v)
        if n < 2: return None
        m = sum(s.v)/n; return math.sqrt(sum((a-m)**2 for a in s.v)/(n-1))
    def finalize(s): return s.value()

def _d(x): return datetime.date.fromisoformat(x)

def add_shims(con):  # MySQL functions the SQL files use, for SQLite
    con.create_window_function('stddev_samp', 1, _SD)
    con.create_function('year', 1, lambda x: int(x[:4]))
    con.create_function('dayofweek', 1, lambda x: _d(x).isoweekday() % 7 + 1)
    con.create_function('datediff', 2, lambda a, b: None if a is None or b is None else (_d(a)-_d(b)).days)
    for n, fn in [('ln', math.log), ('exp', math.exp), ('sqrt', math.sqrt), ('power', math.pow)]:
        con.create_function(n, -1 if n == 'power' else 1, lambda *a, fn=fn: None if None in a or (fn is math.log and a[0] <= 0) else fn(*a))

@st.cache_resource
def boot():
    idx = {re.sub(r'[ \-]+', '_', p.stem.lower()): p for p in BASE.rglob('*') if p.suffix.lower() == '.csv'}  # find CSVs anywhere in the repo, any capitalisation
    missing = [f'{f}.csv' for f in FILES if f.lower() not in idx]
    if missing: return None, missing, []
    con = sqlite3.connect(':memory:', check_same_thread=False)
    for f,(t,_) in FILES.items():
        d = pd.read_csv(idx[f.lower()]); d.columns = COLS
        d['date'] = pd.to_datetime(d['date'], format='%d-%B-%Y').dt.strftime('%Y-%m-%d')
        d.sort_values('date').to_sql(t, con, index=False)
    add_shims(con)
    con.execute("CREATE VIEW raw_prices AS " + " UNION ALL ".join(
        f"SELECT '{n}' AS stock, date, close_price FROM {t}" for t, n in FILES.values()))
    blocks, cur = [], dict(id='pre', label='', note=[], sql=[])
    for line in (BASE/'stock_advanced_analysis.sql').read_text().split('\n'):
        s = line.strip(); m = re.match(r'^-- (\d\.\d) (.*)', s)
        if m or re.match(r'^-- PART', s):
            blocks.append(cur)
            if m:
                lab, _, rest = m.group(2).partition(':')
                cur = dict(id=m.group(1), label=lab.strip(), note=[rest.strip()] if rest.strip() else [], sql=[])
            else: cur = dict(id='part', label='', note=[], sql=[])
        elif s.startswith('--'):
            t = s[2:].strip()
            if t and not set(t) <= set('-='): cur['note'].append(t)
        else: cur['sql'].append(line)
    blocks.append(cur)
    for b in blocks:
        b['df'], b['text'] = None, '\n'.join(b['sql']).strip()
        for q in [x.strip() for x in b['text'].split(';') if x.strip()]:
            m = re.match(r'CREATE OR REPLACE VIEW (\w+)', q)
            if m:
                con.execute(f'DROP VIEW IF EXISTS {m.group(1)}'); q = q.replace('CREATE OR REPLACE VIEW', 'CREATE VIEW', 1)
            if re.match(r'(SELECT|WITH)\b', q, re.I): b['df'] = pd.read_sql(q, con)
            else: con.execute(q)
    return con, [], blocks

st.set_page_config(page_title='NSE Stock Analysis in SQL', layout='wide', page_icon='📈')
con, missing, blocks = boot()
if missing:
    st.error(f"Missing files in ./data: {', '.join(missing)}"); st.stop()
B = {b['id']: b for b in blocks if b['df'] is not None}
q = lambda sql: pd.read_sql(sql, con)
S = st.session_state

def bar(d):  # grouped bar chart with data labels
    d = d.to_frame() if isinstance(d, pd.Series) else d; x = d.index.name or 'index'
    s = d.reset_index().melt(x, var_name='metric', value_name='value')
    b = alt.Chart(s).encode(x=alt.X(f'{x}:N', title=None), y=alt.Y('value:Q', title=None), xOffset='metric:N')
    st.altair_chart(b.mark_bar().encode(color='metric:N') + b.mark_text(dy=-6, fontSize=11).encode(text=alt.Text('value:Q', format=',.1f')), width='stretch')

st.markdown('''<style>
.stApp{background-color:#0b0f14;background-image:linear-gradient(rgba(0,200,83,.045) 1px,transparent 1px),linear-gradient(90deg,rgba(0,200,83,.045) 1px,transparent 1px);background-size:34px 34px}
.block-container{padding-top:1.2rem;max-width:1250px}
.tape{overflow:hidden;white-space:nowrap;background:#0f161e;border:1px solid #1f2a36;border-radius:8px;padding:9px 0;margin-bottom:12px;box-shadow:0 0 14px rgba(0,200,83,.12)}
.tape span{display:inline-block;padding-left:100%;animation:scroll 40s linear infinite;font-family:monospace;font-size:14px}
@keyframes scroll{to{transform:translateX(-100%)}} .up{color:#00e676!important}.dn{color:#ff5252!important}
.hero{position:relative;border:1px solid #1f2a36;border-left:5px solid #00c853;border-radius:12px;padding:22px 26px;margin-bottom:14px;overflow:hidden;
 background:linear-gradient(120deg,#0c2a1c 0%,#0f161e 55%,#0b0f14 100%)}
.hero:after{content:"";position:absolute;inset:0;opacity:.35;background:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 120' preserveAspectRatio='none'><polyline fill='none' stroke='%2300e676' stroke-width='2' points='0,100 40,92 80,96 120,70 160,78 200,55 240,62 280,40 320,48 360,30 400,44 440,22 480,30 520,12 560,18 600,6'/></svg>") right bottom/60% 100% no-repeat}
.hero-t{font-size:30px;font-weight:800;letter-spacing:1px;color:#e6edf3;position:relative;z-index:1}.hero-t span{color:#00e676}
.hero-s{color:#9fb0c0;margin:4px 0 12px;position:relative;z-index:1}
.chips{position:relative;z-index:1}.chips b{display:inline-block;background:#0b0f14;border:1px solid #00c853;color:#00e676;border-radius:20px;padding:3px 12px;margin:0 8px 6px 0;font-size:12px;letter-spacing:.8px}
[data-testid=stMetric]{background:#111a22;border:1px solid #1f2a36;border-left:3px solid #00c853;border-radius:10px;padding:10px 14px}
[data-testid=stMetricValue]{color:#00e676}
button[role=tab]{font-weight:600;font-size:14px} button[role=tab][aria-selected=true]{color:#00e676}
h2,h3{border-bottom:1px solid #1f2a36;padding-bottom:4px}
[data-testid=stDataFrame]{border:1px solid #1f2a36;border-radius:8px}
[data-testid=stExpander]{border:1px solid #1f2a36;border-radius:8px;background:#0f161e}
.stButton>button[kind=primary]{background:#00c853;border:0;color:#04120a;font-weight:700}
</style>''', unsafe_allow_html=True)
_t = q("SELECT stock, date, close_price FROM adj_prices WHERE date IN (SELECT DISTINCT date FROM adj_prices ORDER BY date DESC LIMIT 2) ORDER BY stock, date")
_i = []
for _s, _g in _t.groupby('stock'):
    _c = (_g.close_price.iloc[-1] / _g.close_price.iloc[0] - 1) * 100
    _i.append(f"{_s} {_g.close_price.iloc[-1]:,.2f} <b class={'up' if _c >= 0 else 'dn'}>{'▲' if _c >= 0 else '▼'} {abs(_c):.2f}%</b>")
st.markdown(f"<div class=tape><span>{' &nbsp;│&nbsp; '.join(_i)}</span></div>", unsafe_allow_html=True)

def show(i, chart=None):
    b = B[i]; st.markdown(f"**{i} · {b['label']}**")
    if b['note']: st.caption(' '.join(b['note']))
    st.dataframe(b['df'], width='stretch', hide_index=True)
    if chart is not None: chart(b['df'])
    with st.expander('Show SQL'): st.code(b['text'], language='sql')

st.markdown('<div class="hero"><div class="hero-t">📈 NSE STOCK ANALYSIS <span>IN SQL</span></div><div class="hero-s">Golden-cross signals · the bonus-issue data trap · risk-scored recommendations · model comparison</div><div class="chips"><b>6 STOCKS</b><b>889 SESSIONS EACH</b><b>JAN 2015 – JUL 2018</b><b>MYSQL 8 · STREAMLIT</b><b>SQL-FIRST</b></div></div>', unsafe_allow_html=True)
t0, t1, t2, t3, t4, t6, t7, t8, t9, t5 = st.tabs(['Overview', '1 · Data quality', '2 · EDA', '3 · Advanced SQL', '4 · Model comparison',
                                              '5 · Investor profile', '6 · Recommendations', '7 · Methodology & limits', '8 · Time machine', 'SQL playground'])

with t0:
    c = st.columns(4); c[0].metric('Stocks', 6); c[1].metric('Trading days each', 889)
    c[2].metric('From', '2015-01-01'); c[3].metric('To', '2018-07-31')
    st.subheader('Business problem')
    st.write("A retail investor wants rule-based Buy/Sell signals for six NSE stocks they can trust. Raw prices hide non-economic jumps "
             "(bonus issues), which distort returns, moving averages and signals, so the data must be validated before any signal is believed.")
    st.subheader('Objectives')
    st.markdown("1. Clean and validate the data, justifying each decision.\n2. Profile return, risk, correlation and seasonality.\n"
                "3. Apply advanced SQL (windows, CTEs, views, RSI, drawdown, rolling regression).\n"
                "4. Compare signal models on equal terms and test whether any beats buy-and-hold after costs.")
    st.subheader('Key findings')
    st.markdown("- TCS (2018-05-31) and Infosys (2015-06-15) fell about 50% in one day: **1:1 bonus issues**, not crashes. Adjusted, they gain +52.4% and +38.2% instead of losing 23.8% and 30.9%.\n"
                "- Golden-cross signals across all six stocks: 56 Buys and 57 Sells; the assignment's MA 20/50 ranks 3rd of 7 models.\n"
                "- No model beats buy-and-hold on average after 0.1% costs; fewer trades means better results.\n"
                "- Caveat: about 3.8 years of mostly rising prices; no dividends, news or market-wide data.")

with t1:
    st.header('Data preprocessing and quality audit')
    for i in ['0.1', '0.2', '0.3', '0.4']: show(i)
    show('0.6', lambda d: bar(d.set_index('stock')))
    st.subheader('🔎 Corporate-action detector')
    show('4.1')
    st.info('0.5 builds the cleaned view `adj_prices` (prices before each bonus issue divided by 2) that everything else uses.')

with t2:
    st.header('Exploratory data analysis')
    src = st.radio('Price series', ['Bonus-adjusted', 'Raw'], horizontal=True)
    p = q(f"SELECT date, stock, close_price FROM {'adj_prices' if src.startswith('Bonus') else 'raw_prices'} ORDER BY date")
    w = p.pivot(index='date', columns='stock', values='close_price'); st.caption('Rebased to 100 at the first day')
    st.line_chart(w / w.iloc[0] * 100)
    cs = st.selectbox('Candlestick, last 120 sessions (raw prices: TCS shows the bonus-issue cliff)', NAMES, key='cs')
    k = q(f"SELECT date, open_price o, high_price h, low_price l, close_price c FROM {[t for t, n in FILES.values() if n == cs][0]} ORDER BY date DESC LIMIT 120")
    k['date'] = pd.to_datetime(k['date']); cb = alt.Chart(k).encode(x='date:T', color=alt.condition('datum.c >= datum.o', alt.value('#00c853'), alt.value('#ff5252')))
    st.altair_chart(cb.mark_rule().encode(y=alt.Y('l:Q', scale=alt.Scale(zero=False), title='Price'), y2='h:Q') + cb.mark_bar(size=4).encode(y='o:Q', y2='c:Q'), width='stretch')
    show('1.1'); show('1.2')
    show('1.3', lambda d: bar(d.set_index('stock')[['cagr_pct', 'ann_vol_pct']]))
    show('1.4', lambda d: bar(d.set_index('stock')['max_drawdown_pct']))
    show('1.5'); show('1.6')
    def heat(d):
        s = pd.concat([d, d.rename(columns={'stock_a': 'stock_b', 'stock_b': 'stock_a'}), pd.DataFrame({'stock_a': NAMES, 'stock_b': NAMES, 'corr': 1.0})])
        h = alt.Chart(s).encode(x='stock_a:N', y='stock_b:N')
        st.altair_chart(h.mark_rect().encode(color=alt.Color('corr:Q', scale=alt.Scale(scheme='blues', domain=[0, 1]))) +
                        h.mark_text().encode(text=alt.Text('corr:Q', format='.2f')), width='stretch')
    show('1.7', heat)

with t3:
    st.header('Advanced SQL analysis')
    for i in ['2.1', '2.2', '2.3']: show(i)
    st.subheader('Golden-cross signal explorer (the assignment signal)')
    c1, c2 = st.columns(2)
    name = c1.selectbox('Stock', NAMES, index=4); price = c2.radio('Prices', ['Raw (as given)', 'Bonus-adjusted'], horizontal=True)
    sig_sql = f"""WITH p AS (SELECT date, close_price AS c, ROW_NUMBER() OVER (ORDER BY date) AS rn FROM {'raw_prices' if price.startswith('Raw') else 'adj_prices'} WHERE stock = '{name}'),
m AS (SELECT *, CASE WHEN rn >= 20 THEN AVG(c) OVER (ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
  CASE WHEN rn >= 50 THEN AVG(c) OVER (ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50 FROM p),
l AS (SELECT *, LAG(ma20) OVER (ORDER BY date) AS pm20, LAG(ma50) OVER (ORDER BY date) AS pm50 FROM m)
SELECT date, c AS close_price, ma20, ma50, CASE WHEN ma20 IS NULL OR ma50 IS NULL OR pm20 IS NULL OR pm50 IS NULL THEN 'Hold'
  WHEN ma20 > ma50 AND pm20 <= pm50 THEN 'Buy' WHEN ma20 < ma50 AND pm20 >= pm50 THEN 'Sell' ELSE 'Hold' END AS signal FROM l"""
    s = q(sig_sql); s['date'] = pd.to_datetime(s['date'])
    m = st.columns(3); m[0].metric('Buys', int((s.signal == 'Buy').sum())); m[1].metric('Sells', int((s.signal == 'Sell').sum()))
    m[2].metric('Last signal', (s[s.signal != 'Hold'].iloc[-1].signal + ' · ' + str(s[s.signal != 'Hold'].iloc[-1].date.date())) if (s.signal != 'Hold').any() else '-')
    if name in ('TCS', 'Infosys') and price.startswith('Raw'):
        st.warning('Raw prices contain the bonus-issue cliff, so signals around it can be fake. Switch to Bonus-adjusted to compare.')
    long = s.melt(['date', 'signal'], ['close_price', 'ma20', 'ma50'], 'series', 'price').dropna()
    base = alt.Chart(long).mark_line().encode(x='date:T', y=alt.Y('price:Q', scale=alt.Scale(zero=False)), color='series:N')
    pts = alt.Chart(s[s.signal != 'Hold']).mark_point(size=90, filled=True).encode(
        x='date:T', y=alt.Y('close_price:Q', scale=alt.Scale(zero=False)), color=alt.Color('signal:N', scale=alt.Scale(domain=['Buy', 'Sell'], range=['green', 'red'])), tooltip=['date', 'signal'])
    st.altair_chart(base + pts, width='stretch')
    with st.expander('Show SQL'): st.code(sig_sql, language='sql')

with t4:
    st.header('Systematic model comparison')
    st.caption(' '.join(blocks[[b['id'] for b in blocks].index('3.1') - 1]['note']))
    show('3.2', lambda d: bar(d.set_index('model')['avg_return_pct']))
    st.markdown('**3.1 · Per-stock results**'); sel = st.selectbox('Stock', NAMES, key='m')
    st.dataframe(B['3.1']['df'].query('stock == @sel').sort_values('total_return_pct', ascending=False), hide_index=True, width='stretch')
    eq = q(f"""WITH d AS (SELECT model, date, ret, rn, LAG(pos) OVER (PARTITION BY model ORDER BY date) AS pp, LAG(pos, 2) OVER (PARTITION BY model ORDER BY date) AS pp2
  FROM model_pos WHERE stock = '{sel}'),
t AS (SELECT model, date, pp * ret - CASE WHEN pp <> pp2 THEN 0.001 ELSE 0 END AS nr FROM d WHERE rn > 200 AND pp2 IS NOT NULL)
SELECT model, date, 100 * EXP(SUM(LN(1 + nr)) OVER (PARTITION BY model ORDER BY date)) AS equity FROM t""")
    st.caption('Growth of 100 invested, after costs'); st.line_chart(eq.pivot(index='date', columns='model', values='equity'))
    with st.expander('Show SQL'): st.code(B['3.1']['text'] + '\n\n' + B['3.2']['text'], language='sql')

with t5:
    st.header('SQL playground')
    st.caption('Your own sandbox copy of the database: SELECT, CREATE TABLE ... AS, DROP TABLE IF EXISTS all work, and nothing you do affects other visitors. '
               'Base tables: ' + ', '.join(t for t, _ in FILES.values()) + ' · Views: raw_prices, adj_prices, returns_v, model_pos, rsi_v')
    def new_sandbox():
        c = sqlite3.connect(':memory:', check_same_thread=False); con.backup(c); add_shims(c); return c
    if 'sb' not in S: S['sb'] = new_sandbox()
    tasks = {}
    for part in re.split(r'\n(?=-- Task )', (BASE / 'stock_analysis.sql').read_text())[1:]:
        h, _, body = part.partition('\n'); tasks[h[3:].strip()] = body.strip()
    tasks = {k: v for k, v in tasks.items() if not k.startswith('Task 9')}
    c1, c2 = st.columns([3, 1]); pick = c1.selectbox('Load an assignment task (Task 9, a MySQL function, is excluded)', ['(blank)'] + list(tasks))
    if c2.button('Reset sandbox'): S['sb'] = new_sandbox(); st.toast('Sandbox reset')
    sql = st.text_area('SQL', tasks.get(pick, "SELECT stock, ROUND(AVG(close_price), 2) AS avg_close\nFROM adj_prices GROUP BY stock ORDER BY stock;"), height=260, key=f'sql_{pick}')
    if st.button('▶ Run', type='primary'):
        try:
            r, n = run_sandbox(S['sb'], sql); st.success(f'{n} statement(s) executed')
            if r is not None: st.dataframe(r, width='stretch'); st.download_button('Download CSV', r.to_csv(index=False), 'result.csv')
        except Exception as ex: st.error(f'SQL error: {ex}')
    mine = pd.read_sql("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT IN ('bajaj_auto','eicher_motors','hero_motocorp','infosys','tcs','tvs_motors','raw_prices','adj_prices','returns_v','model_pos','rsi_v','raw_returns','ret_wide','model_eval')", S['sb'])
    if len(mine): st.caption('Objects you created: ' + ', '.join(mine['name']))

DISCLAIMER = ("Educational project, not investment advice. Past performance does not predict future returns. Data covers six NSE stocks "
              "from Jan 2015 to Jul 2018 only; dividends, taxes and market-wide events are ignored. Not a SEBI-registered advisor.")
S = st.session_state; S.setdefault('profile', dict(DEFAULT)); S.setdefault('history', [])

with t6:
    st.header('Investor profile'); p = S['profile']
    up = st.file_uploader('Load a saved profile (.json)', type='json')
    if up is not None:
        try:
            lp = {**DEFAULT, **json.load(up)}; e = validate_profile(lp)
            if e: st.error('; '.join(e))
            else: S['profile'] = p = lp; st.success('Profile loaded')
        except Exception as ex: st.error(f'Could not read that file: {ex}')
    with st.form('profile_form'):
        c1, c2, c3 = st.columns(3); sec = ['Any', 'Auto', 'IT']; gl = list(GOALS)
        nm = c1.text_input('Name', p['name']); age = c1.number_input('Age', 18, 100, int(p['age']))
        dd = c1.slider('Max drawdown I can accept (%)', 5, 60, int(p['max_drawdown_pct'])); rf = c1.number_input('Risk-free rate (%)', 0.0, 15.0, float(p['risk_free_pct']), 0.5)
        cap = c2.number_input('Capital (₹)', 10_000, 10**9, int(p['capital']), 10_000); hz = c2.slider('Horizon (years)', 1, 30, int(p['horizon_years']))
        sp = c2.selectbox('Sector preference', sec, sec.index(p['sector_pref']))
        goal = c3.selectbox('Goal', gl, gl.index(p['goal'])); rt = c3.slider('Risk tolerance (1 low - 5 high)', 1, 5, int(p['risk_tolerance']))
        ns = c3.slider('Number of stocks', 2, 6, int(p['n_stocks']))
        if st.form_submit_button('Save profile'):
            new = dict(name=nm.strip(), age=age, capital=cap, horizon_years=hz, goal=goal, risk_tolerance=rt, max_drawdown_pct=dd,
                       sector_pref=sp, n_stocks=ns, risk_free_pct=rf); e = validate_profile(new)
            if e: st.error('; '.join(e))
            else: S['profile'] = p = new; st.success('Profile saved')
    st.download_button('Download profile (.json)', json.dumps(p, indent=2), 'investor_profile.json', 'application/json')
    st.caption('Goals = goal and horizon · Measurements = capital, risk tolerance, drawdown limit · Preferences = sector, number of stocks · Progress = next tab.')

with t7:
    st.header('Recommendations'); p = S['profile']; st.warning(DISCLAIMER)
    m = B['1.3']['df'].merge(B['1.4']['df'][['stock', 'max_drawdown_pct']], on='stock')
    m['trend'] = m['stock'].map(q("SELECT stock, pos FROM model_pos WHERE model = 'MA 20/50' AND date = (SELECT MAX(date) FROM model_pos)").set_index('stock')['pos'])
    cd = B['1.7']['df']; cm = pd.concat([cd, cd.rename(columns={'stock_a': 'stock_b', 'stock_b': 'stock_a'})]).pivot(index='stock_a', columns='stock_b', values='corr').fillna(1)
    try: rec = recommend(p, m, cm)
    except ValueError as ex: rec = None; st.error(f'Fix your profile first: {ex}')
    with st.expander('How the algorithm works: inputs, logic, expected output', expanded=True):
        a, b_, c = st.columns(3); a.markdown('**Inputs**  \n' + INPUTS); b_.markdown('**Logic**  \n' + LOGIC); c.markdown('**Expected output**  \n' + OUTPUT)
    if rec is not None:
        st.dataframe(rec, hide_index=True, width='stretch'); bar(rec.set_index('stock')[['allocation_pct']])
        if st.button('Log this recommendation to my progress'):
            S['history'].append(dict(time=datetime.datetime.now().strftime('%Y-%m-%d %H:%M'), goal=p['goal'], risk=p['risk_tolerance'], picks=', '.join(rec.stock)))
        st.subheader('Progress: paper portfolio')
        sd = st.date_input('Paper-trade start date', datetime.date(2017, 1, 2), datetime.date(2015, 1, 1), datetime.date(2018, 6, 29))
        try:
            pw = q('SELECT date, stock, close_price FROM adj_prices').pivot(index='date', columns='stock', values='close_price')
            mine = portfolio_curve(pw, dict(zip(rec.stock, rec.amount_inr)), sd.isoformat())
            ew = portfolio_curve(pw, {s_: p['capital'] / 6 for s_ in pw.columns}, sd.isoformat())
            r = mine.pct_change().dropna(); days = (pd.Timestamp(mine.index[-1]) - pd.Timestamp(mine.index[0])).days; cg = cagr(mine.iloc[0], mine.iloc[-1], days)
            st.line_chart(pd.DataFrame({'My portfolio': mine, 'Equal-weight, all six': ew}))
            k = st.columns(5); k[0].metric('Value (₹)', f'{mine.iloc[-1]:,.0f}', f'{100 * (mine.iloc[-1] / mine.iloc[0] - 1):.1f}%')
            k[1].metric('CAGR', f'{100 * cg:.1f}%'); k[2].metric('Volatility', f'{100 * ann_vol(r):.1f}%')
            k[3].metric('Sharpe', f"{sharpe(cg, ann_vol(r), p['risk_free_pct'] / 100):.2f}"); k[4].metric('Max drawdown', f'{100 * max_drawdown(mine):.1f}%')
            st.metric('1-day 95% VaR (historical)', f'₹{var95(r) * mine.iloc[-1]:,.0f}', help='On 95% of past days the loss was smaller than this. It says nothing about the worst 5%.')
        except (ValueError, KeyError) as ex: st.error(f'Could not build the paper portfolio: {ex}')
        st.subheader('Position-size calculator')
        z = st.columns(2); rk = z[0].number_input('Risk per trade (% of capital)', 0.1, 10.0, 1.0, 0.1); sl = z[1].number_input('Stop-loss distance (%)', 0.5, 50.0, 5.0, 0.5)
        st.metric('Suggested position size', f"₹{position_size(p['capital'], rk, sl):,.0f}", help='capital x risk% / stop%, capped at capital')
    if S['history']: st.subheader('My recommendation log'); st.dataframe(pd.DataFrame(S['history']), hide_index=True, width='stretch')

with t8:
    st.header('Methodology and limitations')
    st.graphviz_chart('digraph{rankdir=LR;node[shape=box,style=filled,fillcolor="#131a22",fontcolor=white,color="#00c853"];CSV->"MySQL / SQLite"->"Cleaning views (bonus adjust)"->"SQL metrics: EDA, RSI, signals, models"->"Recommender"->"Streamlit dashboard"}')
    st.markdown("""**Calculations (basic, like BMI for investing):** CAGR, annualised volatility (daily std x sqrt 252), Sharpe ratio ((CAGR - risk-free) / volatility), maximum drawdown, historical 1-day 95% VaR, position size.

**Limitations**
- Only six stocks and 3.6 years; results are period-specific and the window was mostly a rising market.
- Moving-average signals lag price; the 0.1% cost model is a simplification and ignores taxes, dividends and slippage.
- Sharpe depends on the risk-free rate you enter; VaR ignores extreme events; CAGR hides the path taken.
- The recommender is a transparent scoring rule, not a trained or validated forecasting model.
- Bonus-issue dates (TCS 2018-05-31, Infosys 2015-06-15) were found from the data and need confirming against company announcements.

**Setup:** `pip install -r requirements.txt` then `streamlit run app.py`; tests: `pytest`. Deploy on Streamlit Community Cloud with the `data/` folder committed.""")
    st.warning(DISCLAIMER)

with t9:
    st.header('⏳ Time machine: would the recommender have worked?')
    st.markdown("Every 63 trading days (about 3 months), starting after the first year, the recommender sees **only prices up to that day**, "
                "picks stocks for your saved profile, and holds them until the next rebalance (0.1% cost). The benchmark is an equal-weight basket of all six. "
                "There is no look-ahead, so this is an honest test of the recommender itself.")
    try:
        pwx = q('SELECT date, stock, close_price FROM adj_prices').pivot(index='date', columns='stock', values='close_price')
        res, pk = walk_forward(pwx, S['profile']); r1, r2 = res.iloc[-1] - 1
        k = st.columns(4); k[0].metric('Recommender', f'{100 * r1:+.1f}%'); k[1].metric('Equal-weight', f'{100 * r2:+.1f}%')
        k[2].metric('Recommender max drawdown', f'{100 * max_drawdown(res.iloc[:, 0]):.1f}%'); k[3].metric('Equal-weight max drawdown', f'{100 * max_drawdown(res.iloc[:, 1]):.1f}%')
        st.line_chart(res * 100); st.caption('Growth of 100, after costs. Starts after the first year of data.')
        (st.success if r1 > r2 else st.warning)(f"The recommender {'beat' if r1 > r2 else 'trailed'} a simple equal-weight basket by {abs(100 * (r1 - r2)):.1f} percentage points. "
            "Either way this is a finding: a rule-based score built on past risk-adjusted return is not a forecast, and 3.6 years is a short test.")
        st.dataframe(pd.DataFrame(pk, columns=['Rebalance date', 'Stocks held']), hide_index=True, width='stretch')
    except ValueError as ex: st.error(f'Fix your profile first: {ex}')
# -*- coding: utf-8 -*-
"""Presentation layer of the notebooks: tables, decisions, summaries and the aggregate output files.

The code of the English and Spanish notebooks is the same; only LANG in their first code cell differs. Every table is
kept in English in data/outputs_<notebook>.txt (cited by the documents) and, from a Spanish notebook, in Spanish in
data/outputs_<notebook>_es.txt. On screen each table is an HTML table in the language of the notebook.

Publication rule (decision D13): only aggregate counts; in count columns, values from 1 to 4 are shown as "<5".
Nothing here changes a computation.
"""
import builtins
import html as _html
import re

import numpy as np
import pandas as pd

from libraries.i18n import translate

LANG = "en"
SUPPRESS_SMALL = True
lines, lines_es = [], []
_COUNT = ("n", "n_", "events", "admissions", "patients", "deliveries", "count")


def setup(lang):
    """Language of the outputs ("en" or "es"); clears the lines kept for the output files."""
    global LANG
    LANG = lang
    lines.clear(); lines_es.clear()
    pd.set_option("display.max_colwidth", None)


_CODE = re.compile(r"(?<![\w])(?<!Q-)([SG])(\d{1,2})\b")


def _codes(obj):
    """Stage and gate codes of the English labels (S1-S11, G1-G4) as in Spanish (E1-E11, P1-P4)."""
    f = lambda s: _CODE.sub(lambda m: ("E" if m.group(1) == "S" else "P") + m.group(2), s) if isinstance(s, str) else s
    if isinstance(obj, str):
        return f(obj)
    if isinstance(obj, pd.DataFrame):
        o = obj.copy()
        o.columns = [f(c) for c in o.columns]
        o.index = pd.Index([f(i) for i in o.index], name=f(o.index.name))
        for c in o.columns:
            if o[c].dtype == object:
                o[c] = o[c].map(f)
        return o
    return obj


def tr(obj):
    return _codes(translate(obj, "es")) if LANG == "es" else obj


def say(*args):
    """Progress message in the language of the notebook."""
    builtins.print(*[tr(a) if isinstance(a, str) else a for a in args])


def _is_count_col(name):
    name = str(name)
    return name == "n" or name.startswith(_COUNT[1]) or name.split("_")[0] in _COUNT[2:] or name in _COUNT


def _suppress(obj):
    """Counts from 1 to 4 in count columns are replaced by '<5'."""
    if not SUPPRESS_SMALL:
        return obj
    small = lambda v: (isinstance(v, (int, np.integer)) and not isinstance(v, (bool, np.bool_)) and 0 < v < 5)
    if isinstance(obj, pd.DataFrame):
        o = obj.copy()
        for c in o.columns:
            if _is_count_col(c) and (o[c].dtype.kind in "iu" or o[c].dtype == object):
                o[c] = o[c].astype(object).map(lambda v: "<5" if small(v) else v)
        return o
    return obj


def _fmt(v):
    # thousands separator for counts, up to 4 significant digits for small values
    if isinstance(v, (bool, np.bool_)) or v is None or (isinstance(v, float) and np.isnan(v)):
        return v
    if isinstance(v, (int, np.integer)) or (isinstance(v, (float, np.floating)) and float(v).is_integer() and abs(v) >= 1000):
        return f"{int(v):,}"
    if isinstance(v, (float, np.floating)):
        return f"{v:.4g}" if abs(v) < 1 else f"{v:,.4f}".rstrip("0").rstrip(".")
    return v


def _text(title, obj):
    if isinstance(obj, (pd.DataFrame, pd.Series)):
        body = obj.to_string()
    else:
        body = str(obj)
    return f"\n== {title}\n{body}"


def _render(title, obj):
    try:
        from IPython import get_ipython
        from IPython.display import HTML, display
        if get_ipython() is None:
            raise ImportError
    except ImportError:
        return builtins.print(_text(title, obj))
    head = f"<p style='margin:14px 0 4px 0'><b>{_html.escape(str(title))}</b></p>"
    if isinstance(obj, pd.Series):
        obj = obj.to_frame(name=tr("value"))
    if isinstance(obj, pd.DataFrame):
        df = obj.copy().astype(object)
        for k in range(df.shape[1]):
            df.iloc[:, k] = obj.iloc[:, k].map(_fmt)
        table = df.to_html(na_rep="", border=0)
        display(HTML(head + f"<div style='max-height:420px; overflow:auto'>{table}</div>"))
    else:
        display(HTML(head + f"<pre style='margin:0'>{_html.escape(str(obj))}</pre>"))


def show(title, obj, index=False):
    """Show an aggregate table and keep it for the output files (English and, in Spanish, a Spanish copy)."""
    if isinstance(obj, pd.DataFrame) and not index:
        obj = obj.reset_index(drop=True)
        obj.index = range(1, len(obj) + 1)
    obj = _suppress(obj)
    lines.append(_text(title, obj))
    if LANG == "es":
        lines_es.append(_text(_codes(translate(title, "es")), _codes(translate(obj, "es"))))
    _render(tr(title), tr(obj))


def show_results(res, labels):
    """Show the result sets of a SQL script (labels = list of q labels, in order); missing ones are reported."""
    for lab in labels:
        if lab in res:
            show(lab, res[lab])
        else:
            say(f"{lab}: not returned (see the errors of the script)")
    errs = [e for e in res.get("errors", []) if e[0] in labels or not str(e[0]).startswith("Q-")]
    if errs:
        show("Statements of the script that failed", pd.DataFrame(errs, columns=["statement", "error"]))


def check(rows, title):
    """Reference counts: rows of (count, loaded, expected). Returns True if every count is reproduced."""
    df = pd.DataFrame(rows, columns=["count", "loaded", "expected"])
    df["result"] = np.where(df["loaded"] == df["expected"], "reproduced", "DIFFERS")
    show(title, df)
    return bool((df["result"] == "reproduced").all())


def decision(title, rows):
    """Result of a review and the path taken: rows of (review, result, decision)."""
    show(title, pd.DataFrame(rows, columns=["review", "result", "decision"]))


def notebook_summary(rows, title="Notebook summary"):
    """Final table of a notebook: rows of (indicator, value or a function that returns it)."""
    vals = {}
    for k, v in rows:
        try:
            vals[k] = v() if callable(v) else v
        except Exception as exc:                 # noqa: BLE001 -- a missing piece must not hide the rest
            vals[k] = f"not available ({type(exc).__name__})"
    s = pd.Series(vals, name="value", dtype=object)
    s.index.name = "indicator"
    show(title, s.to_frame(), index=True)


def write_outputs(path, header):
    """English output (cited by the documents) and, from the Spanish notebook, a Spanish copy (*_es.txt)."""
    path.parent.mkdir(exist_ok=True)
    path.write_text(header + "\n" + "\n".join(lines) + "\n", encoding="utf-8")
    if LANG == "es":
        path.with_name(path.stem + "_es.txt").write_text(_codes(translate(header, "es")) + "\n" + "\n".join(lines_es) + "\n",
                                                         encoding="utf-8")
    say(f"aggregate output written: data/{path.name}")

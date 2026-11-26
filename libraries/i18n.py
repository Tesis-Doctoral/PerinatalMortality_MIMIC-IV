# -*- coding: utf-8 -*-
"""Spanish labels for the outputs of the notebooks (tables, titles and figures).

The code of the English and Spanish notebooks is the same; only the variable LANG in their first cell differs.
With LANG = "es", `translate()` translates titles, row and column labels and text values of tables (numbers are left as
they are). Strings with numbers inside (for example "99 of 129" or a title with a count) are matched by a
template in which every number is replaced by "#". A label without a translation is shown in English.

The English aggregate outputs (data/outputs_*.txt) are always written: the outcome card, the catalogue and the
scripts cite them. A Spanish notebook also writes a Spanish copy (data/outputs_*_es.txt).
"""
import os
import re

import numpy as np
import pandas as pd

_NUM = re.compile(r"(?<![A-Za-z_])-?\d[\d,]*(?:\.\d+)?")
MISSING = set()                       # labels seen without a translation (to complete ES)

ES = {}                               # filled by i18n_es.py
RULES = []                            # (compiled regex, replacement), filled by i18n_es.py


def _str(s):
    if s in ES:
        return ES[s]
    key = _NUM.sub("#", s)
    if key in ES:
        nums = iter(_NUM.findall(s))
        return re.sub("#", lambda m: next(nums, "#"), ES[key])
    for pat, rep in RULES:                # labels built from a pattern
        m = pat.fullmatch(s)
        if m:
            return rep.format(*[_str(g) if g else "" for g in m.groups()])   # {0}, {1}...: translated groups
    if s.strip() and not _NUM.fullmatch(s.strip()):
        MISSING.add(key)
    return s


def translate(obj, lang="es"):
    """Translate a string, a Series or a DataFrame (labels and text values) to Spanish when lang == "es"."""
    if lang != "es":
        return obj
    if isinstance(obj, (bool, np.bool_)):
        return "Sí" if obj else "No"
    if isinstance(obj, str):
        return _str(obj)
    if isinstance(obj, (pd.Series, pd.DataFrame)):
        o = obj.copy()
        def lab(x):
            return _str(x) if isinstance(x, str) else x
        if isinstance(o.index, pd.MultiIndex):
            o.index = pd.MultiIndex.from_tuples([tuple(lab(v) for v in t) for t in o.index], names=[lab(n) for n in o.index.names])
        else:
            o.index = pd.Index([lab(v) for v in o.index], name=lab(o.index.name))
        if isinstance(o, pd.DataFrame):
            cols = list(o.columns)
            vals = {}
            for k in range(o.shape[1]):
                col = o.iloc[:, k]
                if pd.api.types.is_bool_dtype(col):
                    col = col.map({True: "Sí", False: "No"})
                elif col.dtype == object or pd.api.types.is_string_dtype(col):
                    col = col.map(lambda v: translate(v, lang) if isinstance(v, (str, bool, np.bool_)) else v)
                vals[k] = col
            o = pd.DataFrame(vals, index=o.index)
            o.columns = obj.columns
            if isinstance(o.columns, pd.MultiIndex):
                o.columns = pd.MultiIndex.from_tuples([tuple(lab(v) for v in t) for t in o.columns],
                                                      names=[lab(n) for n in o.columns.names])
            else:
                o.columns = pd.Index([lab(c) for c in o.columns], name=lab(o.columns.name))
        else:
            o.name = lab(o.name)
            if pd.api.types.is_bool_dtype(o):
                o = o.map({True: "Sí", False: "No"})
            elif o.dtype == object or pd.api.types.is_string_dtype(o):
                o = o.map(lambda v: translate(v, lang) if isinstance(v, (str, bool, np.bool_)) else v)
        return o
    return obj


try:                                   # the Spanish dictionary lives in its own file
    from libraries.i18n_es import ES as _ES, RULES as _RULES
    ES.update(_ES)
    RULES.extend((re.compile(p), r) for p, r in _RULES)
except ImportError:
    pass

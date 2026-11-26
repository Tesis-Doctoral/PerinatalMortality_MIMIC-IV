# -*- coding: utf-8 -*-
"""Run the SQL scripts of sql/ from a notebook, as DBeaver does with Alt+X (one connection, every statement in order).

Each audit script is read-only (temporary tables and SELECT). The scripts that build a table of the mimiciv schema
(code catalogue, label tables, unit of analysis, antenatal predictor table) have two parts: the statements that write
the table and the checks (SELECT 'Q-...' AS q). With build=False only the checks run, on the table already in the
database; with build=True the whole script runs and the table is rebuilt.

Every result set that starts with the label column q is returned as {label: DataFrame} (the q column removed). A
statement that fails is rolled back alone (savepoint) and reported in the key "errors"; the rest of the script goes on.
"""
import re
import time

import pandas as pd

# statements that write an object of the mimiciv schema (skipped when build=False)
_WRITES = re.compile(
    r"^\s*(DROP\s+(TABLE|VIEW|INDEX|MATERIALIZED\s+VIEW)\s+(IF\s+EXISTS\s+)?mimiciv\."
    r"|CREATE\s+(OR\s+REPLACE\s+)?(TABLE|VIEW|MATERIALIZED\s+VIEW)\s+mimiciv\."
    r"|CREATE\s+(UNIQUE\s+)?INDEX\b[^;]*?\bON\s+mimiciv\."
    r"|INSERT\s+INTO\s+mimiciv\.|UPDATE\s+mimiciv\.|DELETE\s+FROM\s+mimiciv\.|ALTER\s+TABLE\s+mimiciv\."
    r"|ANALYZE\s+mimiciv\.|COMMENT\s+ON\s+|DO\s)", re.I | re.S)


def split_statements(sql):
    """Split a script on ';' outside comments, quoted strings and dollar-quoted blocks."""
    out, buf, i, n = [], [], 0, len(sql)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):                       # line comment
            j = sql.find("\n", i)
            j = n if j < 0 else j
            buf.append(sql[i:j]); i = j
        elif sql.startswith("/*", i):                     # block comment
            j = sql.find("*/", i + 2)
            j = n if j < 0 else j + 2
            buf.append(sql[i:j]); i = j
        elif c == "'":                                    # string literal ('' escapes a quote)
            j = i + 1
            while j < n:
                if sql[j] == "'" and (j + 1 >= n or sql[j + 1] != "'"):
                    break
                j += 2 if sql[j] == "'" else 1
            buf.append(sql[i:j + 1]); i = j + 1
        elif c == "$":                                    # dollar quote: $$ ... $$ or $tag$ ... $tag$
            m = re.match(r"\$[A-Za-z_]*\$", sql[i:])
            if m:
                tag = m.group(0)
                j = sql.find(tag, i + len(tag))
                j = n if j < 0 else j + len(tag)
                buf.append(sql[i:j]); i = j
            else:
                buf.append(c); i += 1
        elif c == ";":
            out.append("".join(buf)); buf = []; i += 1
        else:
            buf.append(c); i += 1
    out.append("".join(buf))
    return [s for s in out if _code(s).strip()]


def _code(stmt):
    """The statement without its comments (to classify it)."""
    s = re.sub(r"/\*.*?\*/", " ", stmt, flags=re.S)
    return "\n".join(line.split("--", 1)[0] if not line.lstrip().startswith("--") else "" for line in s.splitlines())


def table_exists(engine, name):
    """True if mimiciv.<name> exists (table or view)."""
    with engine.connect() as con:
        r = con.exec_driver_sql(f"SELECT to_regclass('mimiciv.{name}') IS NOT NULL").scalar()
    return bool(r)


def run_script(engine, path, build=False, log=print):
    """Run a script of sql/ in one connection. Returns {q label: DataFrame} plus "errors" (list) and "seconds"."""
    sql = open(path, encoding="utf-8").read()
    stmts = split_statements(sql)
    results, errors, n_run, n_skip = {}, [], 0, 0
    t0 = time.time()
    raw = engine.raw_connection()
    try:
        cur = raw.cursor()
        for k, stmt in enumerate(stmts):
            code = _code(stmt).strip()
            if not build and _WRITES.match(code):
                n_skip += 1
                continue
            cur.execute("SAVEPOINT stmt")
            try:
                cur.execute(stmt)
                n_run += 1
            except Exception as exc:                       # noqa: BLE001 -- reported, the script goes on
                cur.execute("ROLLBACK TO SAVEPOINT stmt")
                label = re.search(r"'(Q-[^']+)'\s+AS\s+q", code)
                errors.append((label.group(1) if label else f"statement {k + 1}", str(exc).splitlines()[0]))
                continue
            if cur.description is not None:
                cols = [d[0] for d in cur.description]
                df = pd.DataFrame(cur.fetchall(), columns=cols)
                if cols and cols[0] == "q" and len(df):
                    label = str(df["q"].iloc[0])
                    df = df.drop(columns="q").reset_index(drop=True)
                    for c in df.columns:                   # Decimal -> float, so tables format as numbers
                        if df[c].dtype == object and df[c].map(lambda v: type(v).__name__ == "Decimal").any():
                            df[c] = pd.to_numeric(df[c], errors="coerce")
                    results[label] = df
            cur.execute("RELEASE SAVEPOINT stmt")
        raw.commit()
    except Exception:
        raw.rollback()
        raise
    finally:
        raw.close()
    results["errors"] = errors
    results["seconds"] = round(time.time() - t0, 1)
    if log:
        mode = "build and checks" if build else "checks only"
        log(f"{path.name}: {n_run} statements run ({mode}), {n_skip} skipped, {len(errors)} errors, "
            f"{results['seconds']} s")
    return results


def ensure_table(engine, name, path, rebuild=False, log=print):
    """Run the script of a mimiciv table: whole script if the table is missing or rebuild=True, else checks only."""
    build = rebuild or not table_exists(engine, name)
    if build and log:
        log(f"building mimiciv.{name} from {path.name}")
    return run_script(engine, path, build=build, log=log)

"""SQLite history of transcriptions."""
import sqlite3
import time
from pathlib import Path

DB_PATH = Path.home() / ".config" / "freeflow" / "freeflow.db"

def _conn():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(str(DB_PATH))
    c.execute("""CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts REAL NOT NULL,
        text TEXT NOT NULL,
        word_count INTEGER NOT NULL DEFAULT 0
    )""")
    return c

def add(text: str) -> int:
    c = _conn()
    words = len(text.split())
    cur = c.execute("INSERT INTO history(ts, text, word_count) VALUES (?, ?, ?)",
                    (time.time(), text, words))
    c.commit()
    id_ = cur.lastrowid
    c.close()
    return id_

def recent(limit=50) -> list[dict]:
    c = _conn()
    rows = c.execute(
        "SELECT id, ts, text, word_count FROM history ORDER BY ts DESC LIMIT ?",
        (limit,)).fetchall()
    c.close()
    return [{"id": r[0], "ts": r[1], "text": r[2], "word_count": r[3]} for r in rows]

def stats() -> dict:
    c = _conn()
    total_words = c.execute("SELECT COALESCE(SUM(word_count), 0) FROM history").fetchone()[0]
    total_count = c.execute("SELECT COUNT(*) FROM history").fetchone()[0]
    # streak: consecutive days with >=1 dictation
    days = [r[0] for r in c.execute(
        "SELECT DISTINCT date(ts, 'unixepoch', 'localtime') FROM history ORDER BY 1 DESC").fetchall()]
    streak = 0
    from datetime import date, timedelta
    today = date.today().isoformat()
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    for i, d in enumerate(days):
        if d == today or d == yesterday:
            streak += 1
        else:
            break
    c.close()
    return {"total_words": total_words, "total_count": total_count, "streak_days": streak}

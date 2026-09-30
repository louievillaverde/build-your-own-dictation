#!/usr/bin/env python3
"""One-time import of Wispr Flow history + dictionary into Dictation. Read-only on Wispr's DB; safe to re-run."""
import os, sqlite3, shutil, subprocess, tempfile, datetime as dt
from pathlib import Path

SUPPORT = Path.home() / "Library/Application Support/Dictation"
AUDIO = SUPPORT / "audio"
WISPR = Path.home() / "Library/Application Support/Wispr Flow/flow.sqlite"
NAMES = {"com.apple.Terminal": "Terminal", "com.google.Chrome": "Google Chrome",
         "com.tinyspeck.slackmacgap": "Slack", "com.apple.MobileSMS": "Messages",
         "com.electron.wispr-flow": "Wispr Flow"}

AUDIO.mkdir(parents=True, exist_ok=True)
tmp = Path(tempfile.mkdtemp())
for f in WISPR.parent.glob("flow.sqlite*"):
    shutil.copy(f, tmp / f.name)  # copy with -wal so we read a consistent snapshot without touching Wispr
src = sqlite3.connect(tmp / "flow.sqlite")
dst = sqlite3.connect(SUPPORT / "dictate.sqlite")
dst.execute("""CREATE TABLE IF NOT EXISTS dictations(
  id TEXT PRIMARY KEY, created_at REAL NOT NULL, app_id TEXT, app_name TEXT,
  duration REAL, raw TEXT, text TEXT, engine TEXT, latency_ms INTEGER,
  pasted INTEGER, audio_path TEXT, source TEXT DEFAULT 'dictate')""")

n = a = 0
for tid, ts, app, dur, asr, fmt, pasted, lat, audio in src.execute(
        "select transcriptEntityId,timestamp,app,duration,asrText,formattedText,pastedText,e2eLatency,audio from History"):
    text = (pasted or fmt or asr or "").strip()
    if not text:
        continue
    when = dt.datetime.fromisoformat(ts.replace(" +00:00", "+00:00")).timestamp()
    path = None
    if audio:
        wav = AUDIO / f"wispr-{tid}.wav"; m4a = wav.with_suffix(".m4a")
        if not m4a.exists():
            wav.write_bytes(audio)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "aac", "-b:a", "32k", m4a], check=True)
            wav.unlink()
        path = str(m4a); a += 1
    dst.execute("INSERT OR REPLACE INTO dictations VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (f"wispr-{tid}", when, app or "", NAMES.get(app or "", app or ""), dur or 0, asr or "", text,
                 "wispr", int(lat or 0), 1 if pasted else 0, path, "wispr"))
    n += 1
dst.commit()

# Dictionary: plain words -> vocab, phrase->replacement -> snippets. Skips Wispr's own defaults.
vocab = SUPPORT / "vocab.txt"; snips = SUPPORT / "snippets.tsv"
have_v = set(vocab.read_text().splitlines()) if vocab.exists() else set()
have_s = snips.read_text() if snips.exists() else "# spoken phrase<TAB>what gets typed\n"
for phrase, repl, source in src.execute("select phrase,replacement,source from Dictionary where isDeleted=0"):
    if phrase in ("btw", "Wispr Flow", "my Flow referral"):
        continue
    if repl:
        if phrase + "\t" not in have_s:
            have_s += f"{phrase}\t{' '.join(repl.split())}\n"
    elif phrase not in have_v and "@" not in phrase:
        have_v.add(phrase)
        with vocab.open("a") as f: f.write(phrase + "\n")
snips.write_text(have_s)
print(f"imported {n} dictations ({a} with audio)")

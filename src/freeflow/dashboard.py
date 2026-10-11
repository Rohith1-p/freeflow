"""Dashboard window: stats + transcription history."""
import tkinter as tk
from tkinter import ttk
from datetime import datetime
from . import history


def show_dashboard(app=None):
    root = tk.Tk()
    root.title("Freeflow")
    root.geometry("800x600")
    root.configure(bg="#1e1e2e")

    # Header
    header = tk.Frame(root, bg="#1e1e2e")
    header.pack(fill=tk.X, padx=20, pady=(20, 10))

    tk.Label(header, text="⚡ Freeflow", font=("Helvetica", 24, "bold"),
             bg="#1e1e2e", fg="#e9eefa").pack(side=tk.LEFT)
    tk.Label(header, text="  Local model — your voice never leaves this Mac",
             font=("Helvetica", 11), bg="#1e1e2e", fg="#7cc0ff").pack(side=tk.LEFT, pady=(8, 0))

    # Instruction card
    card = tk.Frame(root, bg="#2a2a3e", bd=1, relief=tk.FLAT)
    card.pack(fill=tk.X, padx=20, pady=5)
    key = app.cfg.hotkey_key if app else "ctrl"
    tk.Label(card, text=f"\n  Hold [{key.upper()}] to dictate",
             font=("Helvetica", 14), bg="#2a2a3e", fg="#e9eefa").pack()
    tk.Label(card, text="  Works in every app. Your voice stays on this Mac.\n",
             font=("Helvetica", 10), bg="#2a2a3e", fg="#77809a").pack()

    # Stats row
    stats_frame = tk.Frame(root, bg="#1e1e2e")
    stats_frame.pack(fill=tk.X, padx=20, pady=10)

    stats = history.stats()
    stat_data = [
        (f"{stats['total_words']:,}", "words total"),
        (f"{stats['total_count']:,}", "dictations"),
        (f"{stats['streak_days']}", "day streak"),
    ]
    for i, (value, label) in enumerate(stat_data):
        box = tk.Frame(stats_frame, bg="#2a2a3e", padx=15, pady=10)
        box.grid(row=0, column=i, padx=5, sticky="ew")
        stats_frame.columnconfigure(i, weight=1)
        tk.Label(box, text=value, font=("Helvetica", 20, "bold"),
                 bg="#2a2a3e", fg="#7cc0ff").pack()
        tk.Label(box, text=label, font=("Helvetica", 10),
                 bg="#2a2a3e", fg="#77809a").pack()

    # History list
    tk.Label(root, text="Recent transcriptions", font=("Helvetica", 12, "bold"),
             bg="#1e1e2e", fg="#e9eefa").pack(anchor="w", padx=20, pady=(10, 5))

    list_frame = tk.Frame(root, bg="#1e1e2e")
    list_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=(0, 20))

    scrollbar = tk.Scrollbar(list_frame)
    scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

    canvas = tk.Canvas(list_frame, bg="#2a2a3e", highlightthickness=0, yscrollcommand=scrollbar.set)
    canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
    scrollbar.config(command=canvas.yview)

    inner = tk.Frame(canvas, bg="#2a2a3e")
    canvas.create_window((0, 0), window=inner, anchor="nw")

    entries = history.recent(50)
    current_day = None
    for entry in entries:
        day = datetime.fromtimestamp(entry["ts"]).strftime("%B %d")
        if day != current_day:
            current_day = day
            tk.Label(inner, text=day.upper(), font=("Helvetica", 9, "bold"),
                     bg="#2a2a3e", fg="#5b6478").pack(anchor="w", padx=10, pady=(10, 2))
        time_str = datetime.fromtimestamp(entry["ts"]).strftime("%I:%M %p")
        row = tk.Frame(inner, bg="#2a2a3e")
        row.pack(fill=tk.X, padx=10, pady=2)
        tk.Label(row, text=time_str, font=("Helvetica", 10),
                 bg="#2a2a3e", fg="#5b6478", width=8, anchor="w").pack(side=tk.LEFT)
        tk.Label(row, text=entry["text"][:80] + ("..." if len(entry["text"]) > 80 else ""),
                 font=("Helvetica", 10), bg="#2a2a3e", fg="#e9eefa",
                 anchor="w", wraplength=550).pack(side=tk.LEFT, fill=tk.X, expand=True)

    if not entries:
        tk.Label(inner, text="\nNo transcriptions yet.\nHold your key and speak!",
                 font=("Helvetica", 12), bg="#2a2a3e", fg="#5b6478").pack(pady=40)

    def update_scroll(event):
        canvas.configure(scrollregion=canvas.bbox("all"))
    inner.bind("<Configure>", update_scroll)

    root.mainloop()

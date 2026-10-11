"""Settings window: hotkey, model download, general."""
import tkinter as tk
from tkinter import ttk
import threading
import subprocess
from . import config


def show_settings(app):
    root = tk.Tk()
    root.title("Freeflow Settings")
    root.geometry("500x450")
    root.configure(bg="#1e1e2e")

    # HOTKEY section
    tk.Label(root, text="HOTKEY", font=("Helvetica", 11, "bold"),
             bg="#1e1e2e", fg="#7cc0ff").pack(anchor="w", padx=20, pady=(20, 5))

    hotkey_frame = tk.Frame(root, bg="#1e1e2e")
    hotkey_frame.pack(fill=tk.X, padx=20)

    current_key = tk.StringVar(value=app.cfg.hotkey_key.upper())
    tk.Label(hotkey_frame, text="Current:", font=("Helvetica", 11),
             bg="#1e1e2e", fg="#e9eefa").pack(side=tk.LEFT)
    key_label = tk.Label(hotkey_frame, textvariable=current_key,
                          font=("Helvetica", 12, "bold"), bg="#2a2a3e",
                          fg="#7cc0ff", padx=15, pady=5)
    key_label.pack(side=tk.LEFT, padx=10)

    def record_hotkey():
        """Capture next key press as the new hotkey."""
        current_key.set("Press a key...")
        from pynput import keyboard

        def on_press(key):
            key_name = None
            if hasattr(key, "name"):
                key_name = key.name
            elif hasattr(key, "char") and key.char:
                key_name = key.char
            if key_name and key_name not in ("shift", "shift_r", "ctrl_r"):
                current_key.set(key_name.upper())
                app.set_hotkey(key_name)
                listener.stop()

        listener = keyboard.Listener(on_press=on_press)
        listener.start()

    tk.Button(hotkey_frame, text="Change Key", command=record_hotkey,
              bg="#3a4157", fg="#e9eefa", font=("Helvetica", 10),
              relief=tk.FLAT, padx=15, pady=5, cursor="hand2").pack(side=tk.LEFT, padx=10)

    tk.Label(root, text="Hold this key while speaking, release to paste.",
             font=("Helvetica", 9), bg="#1e1e2e", fg="#5b6478").pack(anchor="w", padx=20)

    # MODEL section
    tk.Label(root, text="\nMODEL", font=("Helvetica", 11, "bold"),
             bg="#1e1e2e", fg="#7cc0ff").pack(anchor="w", padx=20, pady=(15, 5))

    model_frame = tk.Frame(root, bg="#1e1e2e")
    model_frame.pack(fill=tk.X, padx=20)

    tk.Label(model_frame, text="Parakeet Redux — 178MB — runs on-device",
             font=("Helvetica", 11), bg="#1e1e2e", fg="#e9eefa").pack(side=tk.LEFT)

    dl_status = tk.StringVar(value="")

    def download_model():
        dl_status.set("Downloading (178MB)...")
        def work():
            import subprocess
            r = subprocess.run(
                [sys.executable, "-c",
                 "import moondream as md; md.photon('moondream/parakeet-redux', device='cpu')"],
                capture_output=True, text=True, timeout=600)
            if r.returncode == 0:
                dl_status.set("✓ Model ready")
            else:
                dl_status.set("Download failed — check internet")
        threading.Thread(target=work, daemon=True).start()

    import sys
    tk.Button(model_frame, text="Re-download", command=download_model,
              bg="#3a4157", fg="#e9eefa", font=("Helvetica", 10),
              relief=tk.FLAT, padx=15, pady=5, cursor="hand2").pack(side=tk.RIGHT)
    tk.Label(root, textvariable=dl_status, font=("Helvetica", 10),
             bg="#1e1e2e", fg="#7cc0ff").pack(anchor="w", padx=20)

    # GENERAL section
    tk.Label(root, text="\nGENERAL", font=("Helvetica", 11, "bold"),
             bg="#1e1e2e", fg="#7cc0ff").pack(anchor="w", padx=20, pady=(15, 5))

    general_frame = tk.Frame(root, bg="#1e1e2e")
    general_frame.pack(fill=tk.X, padx=20)

    login_var = tk.BooleanVar(value=app.cfg.start_at_login)
    def toggle_login():
        app.cfg.start_at_login = login_var.get()
        config.save(app.cfg)
    tk.Checkbutton(general_frame, text="Start at login", variable=login_var,
                   command=toggle_login, bg="#1e1e2e", fg="#e9eefa",
                   selectcolor="#2a2a3e", font=("Helvetica", 11)).pack(anchor="w")

    # Buttons
    btn_frame = tk.Frame(root, bg="#1e1e2e")
    btn_frame.pack(fill=tk.X, padx=20, pady=20)

    def close():
        root.destroy()
    tk.Button(btn_frame, text="Done", command=close,
              bg="#3a4157", fg="#e9eefa", font=("Helvetica", 11),
              relief=tk.FLAT, padx=25, pady=8, cursor="hand2").pack(side=tk.RIGHT)

    root.mainloop()

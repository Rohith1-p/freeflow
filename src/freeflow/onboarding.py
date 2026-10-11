"""First-launch onboarding wizard. 6 screens, ~60 seconds."""
import tkinter as tk
from tkinter import ttk
import threading
import time
import subprocess


def check_accessibility() -> bool:
    """Try creating a CGEventTap. Returns True if permission granted."""
    try:
        from Quartz import (CGEventTapCreate, kCGSessionEventTap,
                           kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                           CGEventMaskBit, kCGEventKeyDown)
        tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                              kCGEventTapOptionListenOnly,
                              CGEventMaskBit(kCGEventKeyDown), None, None)
        return tap is not None
    except Exception:
        return False


def check_microphone() -> bool:
    """Check if mic permission is granted via pyobjc."""
    try:
        import AVFoundation
        status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
            AVFoundation.AVMediaTypeAudio)
        return status == 3  # AVAuthorizationStatusAuthorized
    except Exception:
        # If pyobjc AVFoundation not available, assume granted (sounddevice will fail loudly if not)
        return True


class OnboardingWizard:
    def __init__(self, app):
        self.app = app
        self.root = tk.Tk()
        self.root.title("Freeflow Setup")
        self.root.geometry("600x450")
        self.root.configure(bg="#1e1e2e")
        self.screen = 0
        self.show_welcome()

    def clear(self):
        for widget in self.root.winfo_children():
            widget.destroy()

    def show_welcome(self):
        self.clear()
        tk.Label(self.root, text="⚡ Freeflow", font=("Helvetica", 32, "bold"),
                 bg="#1e1e2e", fg="#7cc0ff").pack(pady=(60, 10))
        tk.Label(self.root, text="Hold a key, speak, your words appear anywhere.",
                 font=("Helvetica", 14), bg="#1e1e2e", fg="#e9eefa").pack()
        tk.Label(self.root, text="\nLocal model. No cloud. No account. No subscription.\n",
                 font=("Helvetica", 11), bg="#1e1e2e", fg="#5b6478").pack()

        tk.Button(self.root, text="Get Started", command=self.show_microphone,
                  bg="#3a4157", fg="#e9eefa", font=("Helvetica", 13),
                  relief=tk.FLAT, padx=30, pady=10, cursor="hand2").pack(pady=40)

    def show_microphone(self):
        self.clear()
        self.screen = 2
        tk.Label(self.root, text="Microphone Access", font=("Helvetica", 20, "bold"),
                 bg="#1e1e2e", fg="#e9eefa").pack(pady=(40, 10))
        status = tk.StringVar(value="Checking..." if not check_microphone() else "✓ Granted")

        tk.Label(self.root, textvariable=status, font=("Helvetica", 13),
                 bg="#1e1e2e", fg="#7cc0ff").pack(pady=5)
        tk.Label(self.root, text="Freeflow needs microphone access to hear you speak.\n"
                                 "macOS will prompt — click Allow.",
                 font=("Helvetica", 11), bg="#1e1e2e", fg="#77809a").pack(pady=5)

        def open_settings():
            subprocess.Popen(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"])

        tk.Button(self.root, text="Open Microphone Settings",
                  command=open_settings, bg="#3a4157", fg="#e9eefa",
                  font=("Helvetica", 11), relief=tk.FLAT, padx=20, pady=8,
                  cursor="hand2").pack(pady=10)

        def poll():
            if check_microphone():
                status.set("✓ Granted!")
                self.root.after(800, self.show_accessibility)
            else:
                self.root.after(2000, poll)
        if not check_microphone():
            # trigger macOS prompt by opening mic briefly
            import sounddevice as sd
            try:
                with sd.InputStream(samplerate=16000, channels=1, dtype="float32"):
                    pass
            except Exception:
                pass
            self.root.after(2000, poll)

        if check_microphone():
            tk.Button(self.root, text="Continue →", command=self.show_accessibility,
                      bg="#3a4157", fg="#e9eefa", font=("Helvetica", 12),
                      relief=tk.FLAT, padx=25, pady=8, cursor="hand2").pack(pady=20)

    def show_accessibility(self):
        self.clear()
        self.screen = 3
        tk.Label(self.root, text="Accessibility Access", font=("Helvetica", 20, "bold"),
                 bg="#1e1e2e", fg="#e9eefa").pack(pady=(40, 10))
        status = tk.StringVar(value="Checking..." if not check_accessibility() else "✓ Granted")

        tk.Label(self.root, textvariable=status, font=("Helvetica", 13),
                 bg="#1e1e2e", fg="#7cc0ff").pack(pady=5)
        tk.Label(self.root,
                 text="Freeflow needs accessibility to detect your hotkey and paste text.\n\n"
                      "1. Click 'Open Accessibility Settings' below\n"
                      "2. Click the + button\n"
                      "3. Press Cmd+Shift+G and type: /Applications/Freeflow.app\n"
                      "4. Select Freeflow and click Open\n"
                      "5. Toggle the switch ON",
                 font=("Helvetica", 11), bg="#1e1e2e", fg="#77809a",
                 justify=tk.LEFT).pack(pady=10)

        def open_settings():
            subprocess.Popen(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])

        tk.Button(self.root, text="Open Accessibility Settings",
                  command=open_settings, bg="#3a4157", fg="#e9eefa",
                  font=("Helvetica", 11), relief=tk.FLAT, padx=20, pady=8,
                  cursor="hand2").pack(pady=5)

        def poll():
            if check_accessibility():
                status.set("✓ Granted!")
                self.root.after(800, self.show_model)
            else:
                self.root.after(2000, poll)
        self.root.after(2000, poll)

    def show_model(self):
        self.clear()
        self.screen = 4
        tk.Label(self.root, text="Download Model", font=("Helvetica", 20, "bold"),
                 bg="#1e1e2e", fg="#e9eefa").pack(pady=(40, 10))

        progress = tk.DoubleVar(value=0)
        status = tk.StringVar(value="Starting download...")

        bar = ttk.Progressbar(self.root, variable=progress, length=350,
                              mode="determinate", maximum=100)
        bar.pack(pady=10)
        tk.Label(self.root, textvariable=status, font=("Helvetica", 11),
                 bg="#1e1e2e", fg="#7cc0ff").pack()

        def download():
            import sys
            status.set("Downloading Parakeet Redux (178MB)...")
            progress.set(10)
            r = subprocess.run(
                [sys.executable, "-c",
                 "import moondream as md\nmd.photon('moondream/parakeet-redux', device='cpu')"],
                capture_output=True, text=True, timeout=600)
            if r.returncode == 0:
                progress.set(100)
                status.set("✓ Model ready")
                self.root.after(1000, self.show_key_choice)
            else:
                status.set("Download failed. Click to retry.")
                progress.set(0)
                tk.Button(self.root, text="Retry", command=download,
                          bg="#3a4157", fg="#e9eefa", relief=tk.FLAT,
                          padx=20, pady=5, cursor="hand2").pack()

        def skip():
            self.show_key_choice()

        # Check if already cached
        import os
        model_path = os.path.expanduser("~/.cache/huggingface/hub/models--moondream--parakeet-redux")
        if os.path.exists(model_path):
            status.set("✓ Model already downloaded")
            tk.Button(self.root, text="Continue →", command=self.show_key_choice,
                      bg="#3a4157", fg="#e9eefa", font=("Helvetica", 12),
                      relief=tk.FLAT, padx=25, pady=8, cursor="hand2").pack(pady=20)
        else:
            threading.Thread(target=download, daemon=True).start()
            tk.Button(self.root, text="Skip for now", command=skip,
                      bg="#1e1e2e", fg="#5b6478", font=("Helvetica", 10),
                      relief=tk.FLAT, cursor="hand2").pack(pady=10)

    def show_key_choice(self):
        self.clear()
        self.screen = 5
        tk.Label(self.root, text="Choose Your Key", font=("Helvetica", 20, "bold"),
                 bg="#1e1e2e", fg="#e9eefa").pack(pady=(40, 10))
        tk.Label(self.root, text="Press the key you want to HOLD while speaking.",
                 font=("Helvetica", 12), bg="#1e1e2e", fg="#77809a").pack()

        chosen = tk.StringVar(value="(press a key)")

        from pynput import keyboard
        def on_press(key):
            key_name = None
            if hasattr(key, "name"):
                key_name = key.name
            elif hasattr(key, "char") and key.char:
                key_name = key.char
            if key_name and key_name not in ("shift", "shift_r", "ctrl_r", "alt_r", "cmd_r"):
                chosen.set(key_name.upper())
                self.app.set_hotkey(key_name)
                listener.stop()

        listener = keyboard.Listener(on_press=on_press)
        listener.start()

        big_label = tk.Label(self.root, textvariable=chosen,
                              font=("Helvetica", 36, "bold"),
                              bg="#2a2a3e", fg="#7cc0ff",
                              padx=40, pady=20)
        big_label.pack(pady=20)

        tk.Label(self.root, text="Suggested: ctrl (hold left Control)",
                 font=("Helvetica", 10), bg="#1e1e2e", fg="#5b6478").pack()

        def next_screen():
            listener.stop()
            self.show_done()
        tk.Button(self.root, text="Set & Continue →", command=next_screen,
                  bg="#3a4157", fg="#e9eefa", font=("Helvetica", 12),
                  relief=tk.FLAT, padx=25, pady=8, cursor="hand2").pack(pady=30)

    def show_done(self):
        self.clear()
        self.screen = 6
        tk.Label(self.root, text="🎉 You're Ready!", font=("Helvetica", 24, "bold"),
                 bg="#1e1e2e", fg="#7cc0ff").pack(pady=(50, 10))
        key = self.app.cfg.hotkey_key.upper()
        tk.Label(self.root, text=f"Hold [{key}] and speak.\nYour words appear wherever your cursor is.",
                 font=("Helvetica", 13), bg="#1e1e2e", fg="#e9eefa").pack()

        from . import config
        config.mark_onboarding_complete()

        def open_test():
            import tkinter as tk2
            test = tk2.Toplevel(self.root)
            test.title("Test Window")
            test.geometry("400x200")
            text = tk2.Text(test, font=("Helvetica", 14), wrap=tk2.WORD)
            text.pack(fill=tk2.BOTH, expand=True)
            text.insert("1.0", "Click here, hold your key, and speak...\n\n")

        def finish():
            self.root.destroy()
            self.app.start()

        tk.Button(self.root, text="Open Test Window", command=open_test,
                  bg="#3a4157", fg="#e9eefa", font=("Helvetica", 11),
                  relief=tk.FLAT, padx=20, pady=8, cursor="hand2").pack(pady=10)
        tk.Button(self.root, text="Start Dictating →", command=finish,
                  bg="#3a4157", fg="#e9eefa", font=("Helvetica", 13),
                  relief=tk.FLAT, padx=30, pady=10, cursor="hand2").pack(pady=15)

    def run(self):
        self.root.mainloop()


def run_onboarding(app):
    wizard = OnboardingWizard(app)
    wizard.run()

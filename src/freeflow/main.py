"""Freeflow - local dictation for Mac. Entry point."""
import os
import sys
import threading
import time

from . import config
from .audio import Recorder
from .transcriber import Transcriber
from .paster import paste_text
from .hotkey import HotkeyListener
from . import history


def beep(sound="Tink"):
    os.system(f"afplay /System/Library/Sounds/{sound}.aiff &")


class FreeflowApp:
    def __init__(self):
        self.cfg = config.load()
        self.recorder = Recorder(sample_rate=self.cfg.sample_rate)
        self.transcriber = Transcriber(model_id=self.cfg.model_id, device=self.cfg.device)
        self.hotkey = HotkeyListener(
            key_name=self.cfg.hotkey_key,
            on_press=self._on_hotkey_press,
            on_release=self._on_hotkey_release,
        )
        self.is_running = False
        self.menubar = None

    def _on_hotkey_press(self):
        self.recorder.start_recording()
        beep("Tink")
        if self.menubar:
            self.menubar.set_recording(True)

    def _on_hotkey_release(self, duration_s):
        if self.menubar:
            self.menubar.set_recording(False)
        audio = self.recorder.stop_recording(min_duration_s=self.cfg.min_duration_s)
        if audio is None:
            return

        def work():
            try:
                beep("Pop")
                tmp = "/tmp/freeflow_dictation.wav"
                self.recorder.save_wav(audio, tmp)
                text = self.transcriber.transcribe_file(tmp)
                if text:
                    paste_text(text)
                    history.add(text)
            except Exception as e:
                print(f"dictation error: {e}", flush=True)
        threading.Thread(target=work, daemon=True).start()

    def start(self):
        self.recorder.start_stream()
        self.hotkey.start()
        self.is_running = True
        print("Freeflow ready. Hold key to talk, release to paste.")

    def stop(self):
        self.hotkey.stop()
        self.is_running = False

    def set_hotkey(self, key_name):
        self.cfg.hotkey_key = key_name
        config.save(self.cfg)
        self.hotkey.set_key(key_name)


def run():
    """Main entry point. Menu bar mode with onboarding on first run."""
    app = FreeflowApp()

    if not config.onboarding_complete():
        from .onboarding import run_onboarding
        run_onboarding(app)

    from .menubar import FreeflowMenuBar
    app.menubar = FreeflowMenuBar(app)
    app.start()
    app.menubar.run()


def run_cli():
    """Standalone CLI mode (no menu bar). For testing."""
    app = FreeflowApp()
    app.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        app.stop()
        print("Freeflow stopped.")


if __name__ == "__main__":
    run()

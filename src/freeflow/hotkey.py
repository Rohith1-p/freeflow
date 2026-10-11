"""Global hotkey listener. Press-and-hold to record."""
import time
import threading
from pynput import keyboard

class HotkeyListener:
    def __init__(self, key_name="ctrl", on_press=None, on_release=None):
        self.key_name = key_name
        self.on_press = on_press
        self.on_release = on_release
        self._down_since = None
        self._listening = False
        self._listener = None

    def _get_key(self):
        return getattr(keyboard.Key, self.key_name, None)

    def _on_press(self, key):
        if key == self._get_key() and self._down_since is None:
            self._down_since = time.time()
            self._listening = True
            if self.on_press:
                self.on_press()

    def _on_release(self, key):
        if key == self._get_key() and self._listening:
            dur = time.time() - (self._down_since or 0)
            self._listening = False
            self._down_since = None
            if self.on_release:
                self.on_release(dur)

    def start(self):
        self._listener = keyboard.Listener(
            on_press=self._on_press, on_release=self._on_release)
        self._listener.start()

    def stop(self):
        if self._listener:
            self._listener.stop()
            self._listener = None

    def set_key(self, key_name: str):
        self.key_name = key_name

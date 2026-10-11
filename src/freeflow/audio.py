"""Microphone recording via sounddevice. Always-open mic, buffer on demand."""
import threading
import numpy as np
import sounddevice as sd

class Recorder:
    def __init__(self, sample_rate=16000):
        self.sample_rate = sample_rate
        self.q_frames = []
        self.recording = False
        self.lock = threading.Lock()
        self._stream = None

    def _callback(self, indata, frames, time_info, status):
        if self.recording:
            with self.lock:
                self.q_frames.append(indata.copy())

    def start_stream(self):
        if self._stream is None:
            self._stream = sd.InputStream(
                samplerate=self.sample_rate, channels=1, dtype="float32",
                callback=self._callback, blocksize=1024)
            self._stream.start()

    def start_recording(self):
        with self.lock:
            self.q_frames = []
        self.recording = True

    def stop_recording(self, min_duration_s=0.4) -> np.ndarray | None:
        self.recording = False
        with self.lock:
            if not self.q_frames:
                return None
            audio = np.concatenate(self.q_frames, axis=0)
        if len(audio) < self.sample_rate * min_duration_s:
            return None
        return audio.flatten().astype(np.float32)

    def save_wav(self, audio: np.ndarray, path: str):
        import wave
        with wave.open(path, "w") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(self.sample_rate)
            w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())

"""Parakeet Redux local transcription wrapper. Lazy model load."""
import os

os.environ.setdefault("HF_HOME", os.path.expanduser("~/.cache/huggingface"))
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")

class Transcriber:
    def __init__(self, model_id="moondream/parakeet-redux", device="cpu"):
        self.model_id = model_id
        self.device = device
        self._model = None

    def _load(self):
        if self._model is not None:
            return
        import moondream as md
        self._model = md.photon(self.model_id, device=self.device)

    def transcribe_file(self, wav_path: str) -> str:
        self._load()
        result = self._model.transcribe(audio=wav_path)
        return (result.get("text") or "").strip()

    def transcribe_audio(self, audio, tmp_path="/tmp/freeflow_dictation.wav"):
        import numpy as np
        from .audio import Recorder
        # audio is float32 numpy array; save to wav then transcribe
        rec = Recorder()  # just for save_wav utility
        rec.save_wav(audio, tmp_path)
        return self.transcribe_file(tmp_path)

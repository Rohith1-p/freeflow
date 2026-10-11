"""Freeflow configuration: TOML at ~/.config/freeflow/config.toml"""
import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "freeflow"
CONFIG_PATH = CONFIG_DIR / "config.toml"

@dataclass
class Config:
    hotkey_key: str = "ctrl"           # pynput key name
    model_id: str = "moondream/parakeet-redux"
    device: str = "cpu"                # cpu | mps
    sample_rate: int = 16000
    min_duration_s: float = 0.4
    start_at_login: bool = True
    log_queries: bool = False

def load() -> Config:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, "rb") as f:
                data = tomllib.load(f)
            cfg = Config()
            if "hotkey" in data:
                cfg.hotkey_key = data["hotkey"].get("key", cfg.hotkey_key)
            if "transcription" in data:
                cfg.model_id = data["transcription"].get("model", cfg.model_id)
                cfg.device = data["transcription"].get("device", cfg.device)
            if "audio" in data:
                cfg.sample_rate = data["audio"].get("sample_rate", cfg.sample_rate)
                cfg.min_duration_s = data["audio"].get("min_duration_s", cfg.min_duration_s)
            if "general" in data:
                cfg.start_at_login = data["general"].get("start_at_login", cfg.start_at_login)
                cfg.log_queries = data["general"].get("log_queries", cfg.log_queries)
            return cfg
        except Exception:
            pass
    return Config()  # defaults

def save(cfg: Config):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        "[hotkey]",
        f'key = "{cfg.hotkey_key}"',
        "",
        "[transcription]",
        f'model = "{cfg.model_id}"',
        f'device = "{cfg.device}"',
        "",
        "[audio]",
        f"sample_rate = {cfg.sample_rate}",
        f"min_duration_s = {cfg.min_duration_s}",
        "",
        "[general]",
        f"start_at_login = {'true' if cfg.start_at_login else 'false'}",
        f"log_queries = {'true' if cfg.log_queries else 'false'}",
        "",
    ]
    CONFIG_PATH.write_text("\n".join(lines))

def onboarding_complete() -> bool:
    return (CONFIG_DIR / "onboarding_complete").exists()

def mark_onboarding_complete():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    (CONFIG_DIR / "onboarding_complete").touch()

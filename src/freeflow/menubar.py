"""Menu bar icon + dropdown via rumps."""
import rumps
from . import config


class FreeflowMenuBar(rumps.App):
    def __init__(self, app_instance):
        super().__init__(name="Freeflow", icon=None, title="🎙", quit_button=None)
        self.app = app_instance
        self.is_recording = False

        # Menu items
        self.menu = [
            rumps.MenuItem("Dashboard", callback=self.on_dashboard),
            rumps.MenuItem("Settings", callback=self.on_settings),
            None,  # separator
            rumps.MenuItem("Start Dictation", callback=self.on_toggle),
            None,  # separator
            rumps.MenuItem("About Freeflow", callback=self.on_about),
            rumps.MenuItem("Quit", callback=self.on_quit),
        ]
        self.start_item = self.menu["Start Dictation"]

    def on_dashboard(self, sender):
        from .dashboard import show_dashboard
        show_dashboard(self.app)

    def on_settings(self, sender):
        from .settings_ui import show_settings
        show_settings(self.app)

    def on_toggle(self, sender):
        if self.app.is_running:
            self.app.stop()
            sender.title = "Start Dictation"
            self.title = "🎙"
        else:
            self.app.start()
            sender.title = "Stop Dictation"
            self.title = "🔴" if self.is_recording else "🎙"

    def on_about(self, sender):
        rumps.alert(
            title="Freeflow",
            message="Local dictation for Mac.\n\n"
                    "Hold a key, speak, release.\n"
                    "Your words appear at your cursor.\n\n"
                    "Powered by Parakeet Redux (178MB, on-device).\n"
                    "No cloud. No account. No subscription.\n\n"
                    "github.com/rohith1-p/freeflow",
            ok="OK")

    def on_quit(self, sender):
        self.app.stop()
        rumps.quit_application()

    def set_recording(self, recording: bool):
        self.is_recording = recording
        self.title = "🔴" if recording else "🎙"

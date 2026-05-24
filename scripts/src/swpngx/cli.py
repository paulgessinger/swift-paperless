import typer
from swpngx.bezel_frames import download_frames
from swpngx.fonts import download_fonts
from swpngx.devices_cli import check_devices, migrate_prefix
from swpngx.frame import main as frame_cmd
from swpngx.capture import app as capture_app
from swpngx.preview import main as preview_cmd

app = typer.Typer(no_args_is_help=True, help="Swift Paperless automation CLI")

frames_app = typer.Typer(help="Apple Product Bezel assets for screenshot framing")
frames_app.command(
    "download", help="Download bezels from Apple and install frame PNGs"
)(download_frames)

fonts_app = typer.Typer(help="Screenshot framing fonts")
fonts_app.command(
    "download",
    help="Download Open Sans and other fonts from fonts.toml",
)(download_fonts)

devices_app = typer.Typer(help="Screenshot device configuration")
devices_app.command("check", help="Verify devices, bezels, and screenshot files align")(
    check_devices
)
devices_app.command(
    "migrate-prefix",
    help="Rename screenshots that use a legacy device id prefix",
)(migrate_prefix)

app.command("frame", help="Frame screenshots with device frames")(frame_cmd)
app.add_typer(frames_app, name="frames")
app.add_typer(fonts_app, name="fonts")
app.add_typer(devices_app, name="devices")
app.add_typer(capture_app, name="capture", help="Capture screenshots from simulator")
app.command("preview", help="Preview metadata and screenshots in browser")(preview_cmd)

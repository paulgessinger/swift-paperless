import typer
from swpngx.frame import main as frame_cmd
from swpngx.capture import app as capture_app
from swpngx.preview import main as preview_cmd

app = typer.Typer(no_args_is_help=True, help="Swift Paperless automation CLI")

app.command("frame", help="Frame screenshots with device frames")(frame_cmd)
app.add_typer(capture_app, name="capture", help="Capture screenshots from simulator")
app.command("preview", help="Preview metadata and screenshots in browser")(preview_cmd)

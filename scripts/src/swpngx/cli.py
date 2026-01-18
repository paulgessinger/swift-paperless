import typer
from swpngx.frame import app as frame_app
from swpngx.capture import app as capture_app

app = typer.Typer(no_args_is_help=True, help="Swift Paperless automation CLI")

app.add_typer(frame_app, name="frame", help="Frame related commands")
app.add_typer(capture_app, name="capture", help="Capture related commands")

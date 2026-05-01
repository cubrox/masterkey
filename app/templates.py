"""Shared Jinja2 templates instance.

Exported from a single module so routes and tests agree on the template
directory. This also makes it easy to override in tests.
"""

from pathlib import Path

from fastapi.templating import Jinja2Templates

TEMPLATE_DIR = Path(__file__).parent.parent / "templates"

templates = Jinja2Templates(directory=str(TEMPLATE_DIR))

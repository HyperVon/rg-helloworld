# image-pipeline-python

Python image pipeline (Milestone 0 skeleton). Composes glyph PNGs into a
phrase image and prepares images for OCR in later milestones.

## Commands

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/ruff format .              # format
.venv/bin/ruff check .               # lint
.venv/bin/ruff format --check .      # format check
PYTHONPATH=src python3 -m unittest discover -s tests   # unit tests
PYTHONPATH=src .venv/bin/coverage run -m unittest discover -s tests
.venv/bin/coverage report --fail-under=90              # coverage gate
```

Dependencies are pinned in `requirements-dev.txt`: ruff 0.16.1,
coverage 7.15.3. The runtime itself has no dependencies in this milestone.

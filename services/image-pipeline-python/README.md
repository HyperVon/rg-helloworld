# image-pipeline-python

Python image pipeline for the Rube Goldberg Hello World project (Milestone 7).

Composes glyph PNGs into a phrase image and prepares images for OCR.

## Commands

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/ruff format .              # format
.venv/bin/ruff check .               # lint
.venv/bin/ruff format --check .      # format check
PYTHONPATH=src python3 -m unittest discover -s tests   # unit tests
PYTHONPATH=src .venv/bin/coverage run -m unittest discover -s tests
.venv/bin/coverage report --fail-under=90              # coverage gate
python3 -m compileall -q src                           # syntax check
```

## Dependencies

Runtime dependencies (pinned in `requirements-dev.txt`):
- Pillow (image processing)
- numpy (array operations)
- scikit-image (image processing)
- aiokafka (Kafka client for later phases)
- minio (MinIO/S3 client for later phases)
- jsonschema (contract validation)

Lint/format:
- ruff (0.16.1)

Testing:
- coverage (7.15.3)

## CLI

```bash
# Compose phrase image from glyph inputs
python3 -m rg_image_pipeline.cli compose <glyph_files... \
  --output-phrase-image phrase.png \
  --output-manifest manifest.json \
  --scale-factor 2

# Preprocess phrase image for OCR
python3 -m rg_image_pipeline.cli preprocess \
  --phrase-image phrase.png \
  --composition-manifest manifest.json \
  --output-ocr-image ocr.png \
  --output-crops-dir crops/ \
  --output-report report.json
```

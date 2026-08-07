FROM python:3.13-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

FROM base AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-dev.txt .

RUN pip install --no-cache-dir \
    pillow==12.3.0 \
    numpy==2.3.5 \
    scikit-image==0.25.2 \
    aiokafka==0.12.0 \
    minio==7.2.12 \
    jsonschema==4.25.0 \
    python-snappy==0.7.3

COPY src/ ./src/

WORKDIR /app/src
EXPOSE 8080

CMD ["python3", "-m", "rg_image_pipeline.cli", "--version"]

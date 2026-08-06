# Adjudicator: Ruby service for OCR consensus and quality decisions.
# Base image is tag-pinned (never "latest").
FROM ruby:3.4.4-bookworm AS base

WORKDIR /app
COPY . /app/

RUN gem install bundler -v 4.0.16 \
    && bundle config set --local deployment 'true' \
    && bundle install

FROM ruby:3.4.4-bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 && \
    rm -rf /var/lib/apt/lists/*

RUN gem install bundler -v 4.0.16

WORKDIR /app
COPY --from=base /usr/local/bundle /usr/local/bundle
COPY --from=base /app /app

ENV RUBY_ENV=production
ENV KAFKA_BOOTSTRAP=kafka.rube-goldberg.svc.cluster.local:9092
ENV KAFKA_GROUP_ID=adjudicator
ENV OBSERVATIONS_TOPIC=rg.ocr-observations.v1
ENV ADJUDICATED_TOPIC=rg.symbols-adjudicated.v1
ENV QUALITY_RETRY_TOPIC=rg.quality-retry.v1
ENV MINIO_ENDPOINT=minio.rube-goldberg.svc.cluster.local:9000
ENV MINIO_BUCKET=rube-goldberg-artifacts

EXPOSE 4242
COPY bin/adjudicator /usr/local/bin/adjudicator
RUN chmod +x /usr/local/bin/adjudicator

ENTRYPOINT ["bundle", "exec", "/usr/local/bin/adjudicator"]

# Adjudicator: Ruby service for OCR consensus and quality decisions.
# Base image is tag-pinned (never "latest").
# Pinned to RUBY_VERSION=4.0.6 (see versions.env).
FROM ruby:4.0.6-trixie AS base

WORKDIR /app
COPY . /app/

RUN gem install bundler -v 4.0.16 \
    && bundle config set --local deployment 'true' \
    && bundle install

# Pinned to RUBY_VERSION=4.0.6 (see versions.env).
FROM ruby:4.0.6-trixie

RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 libsasl2-2 && \
    rm -rf /var/lib/apt/lists/*

RUN gem install bundler -v 4.0.16

RUN adduser --system --uid 1001 --group --home /nonexistent rghw

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

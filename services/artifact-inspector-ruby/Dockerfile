FROM ruby:3.4-alpine AS runtime
WORKDIR /app
COPY Gemfile Gemfile.lock* ./
COPY lib/ ./lib/
RUN apk add --no-cache build-base \
    && bundle config set --local deployment 'true' \
    && bundle install \
    && apk del build-base
EXPOSE 4568
ENTRYPOINT ["bundle", "exec", "ruby", "-Ilib", "lib/artifact_inspector_server.rb"]

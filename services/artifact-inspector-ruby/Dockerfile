FROM ruby:3.4-alpine AS runtime
WORKDIR /app
COPY Gemfile Gemfile.lock* ./
COPY lib/ ./lib/
RUN apk add --no-cache build-base && gem install sinatra rackup puma --no-document && apk del build-base
EXPOSE 4568
ENTRYPOINT ["ruby", "-Ilib", "lib/artifact_inspector_server.rb"]

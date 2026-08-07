FROM ruby:3.4-alpine AS runtime
WORKDIR /app
COPY Gemfile Gemfile.lock* ./
COPY lib/ ./lib/
RUN gem install sinatra --no-document || true
EXPOSE 4568
ENTRYPOINT ["ruby", "-Ilib", "lib/artifact_inspector.rb"]

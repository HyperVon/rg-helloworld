# adjudicator-ruby

Ruby OCR adjudicator. Performs deterministic OCR consensus and quality
decisions on adjudicated symbol observations and publishes accepted tokens
for the phrase assembler.

## Commands

```bash
bundle install                 # install pinned gems
bundle exec rubocop -A         # format (autocorrect)
bundle exec rubocop            # lint
bundle exec rake test          # unit tests (minitest)
bundle exec ruby -r simplecov test/adjudicator_test.rb   # coverage
```

Pinned in `Gemfile`/`Gemfile.lock`: minitest 6.0.6, rake 13.4.2,
rubocop 1.89.0, simplecov 1.0.3. Ruby 4.0+ (see `.ruby-version`).

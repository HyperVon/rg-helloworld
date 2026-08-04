# adjudicator-ruby

Ruby OCR adjudicator (Milestone 0 skeleton). Performs deterministic OCR
consensus and quality decisions, and hosts the HTMX artifact inspector in
later milestones.

## Commands

```bash
bundle install                 # install pinned gems
bundle exec rubocop -A         # format (autocorrect)
bundle exec rubocop            # lint
bundle exec rake test          # unit tests (minitest)
bundle exec ruby -r simplecov test/adjudicator_test.rb   # coverage
```

Pinned in `Gemfile`/`Gemfile.lock`: minitest 6.0.6, rake 13.2.1,
rubocop 1.89.0, simplecov 1.0.3. Ruby 3.4+ (see `.ruby-version`).

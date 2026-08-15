# rg-artifact-inspector

Ruby artifact browser for Rube Goldberg Hello World.

Serves artifact listings from the event gateway under `/inspector/runs/{runId}`.
Designed to be embedded in an iframe to avoid DOM conflicts with the React shell.

## Usage

```bash
bundle install
ruby -Ilib -e 'require "artifact_inspector"; puts ArtifactInspector.banner'
```

## Tests

```bash
bundle exec ruby -Ilib -Itest test/inspector_test.rb
```

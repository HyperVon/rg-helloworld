# -*- encoding: utf-8 -*-
# stub: ruby-kafka 1.5.0 ruby lib

Gem::Specification.new do |s|
  s.name = "ruby-kafka".freeze
  s.version = "1.5.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Daniel Schierbeck".freeze]
  s.bindir = "exe".freeze
  s.date = "2022-05-25"
  s.description = "A client library for the Kafka distributed commit log.".freeze
  s.email = ["daniel.schierbeck@gmail.com".freeze]
  s.homepage = "https://github.com/zendesk/ruby-kafka".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.1.0".freeze)
  s.rubygems_version = "3.1.2".freeze
  s.summary = "A client library for the Kafka distributed commit log.".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<digest-crc>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 1.9.5".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 10.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<digest-murmurhash>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<dotenv>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<docker-api>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec-benchmark>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<activesupport>.freeze, [">= 4.0".freeze, "< 6.1".freeze])
  s.add_development_dependency(%q<snappy>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<extlz4>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<zstd-ruby>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<colored>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec_junit_formatter>.freeze, ["= 0.2.2".freeze])
  s.add_development_dependency(%q<dogstatsd-ruby>.freeze, [">= 4.0.0".freeze, "< 5.0.0".freeze])
  s.add_development_dependency(%q<statsd-ruby>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<prometheus-client>.freeze, ["~> 0.10.0".freeze])
  s.add_development_dependency(%q<ruby-prof>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<timecop>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 0.49.1".freeze])
  s.add_development_dependency(%q<gssapi>.freeze, [">= 1.2.0".freeze])
  s.add_development_dependency(%q<stackprof>.freeze, [">= 0".freeze])
end

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "seeitlive/version"

Gem::Specification.new do |s|
  s.name        = "seeitlive-sdk"
  s.version     = SeeItLive::VERSION
  s.summary     = "Official SeeItLive SDK for Ruby"
  s.description = "Official SeeItLive SDK for Ruby -- an idiomatic port of the reference " \
                  "@seeitlive/sdk Node client. Create and check invite sessions, verify " \
                  "OAuth tokens, and exchange authorization codes."
  s.authors     = ["SeeItLive"]
  s.license     = "MIT"
  s.homepage    = "https://seeitlive.io"
  s.files       = Dir["lib/**/*.rb"]
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 3.0"

  s.add_development_dependency "minitest", "~> 5.0"
  s.add_development_dependency "webmock", "~> 3.0"
  s.add_development_dependency "rake", "~> 13.0"
end

# frozen_string_literal: true

require_relative "lib/busbar/oneroster/version"

Gem::Specification.new do |spec|
  spec.name          = "busbar-oneroster"
  spec.version       = Busbar::OneRoster::VERSION
  spec.summary       = "OneRoster 1.2 CSV support for the BusBar engine"
  spec.description   = "Reads OneRoster 1.2 CSV zip packages (bulk and delta) and plugs their " \
                       "rostering files into the BusBar Rails engine as schemas, templates and a package handler."
  spec.license       = "MIT"
  spec.authors       = ["BusBar contributors"]
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "csv", ">= 3.2"
  spec.add_dependency "rubyzip", ">= 2.3"
  # The engine itself is a soft dependency: the gem's readers work without it, and
  # registration runs only when the engine fires its :busbar load hook.
  spec.add_development_dependency "minitest", ">= 5.18"
  spec.add_development_dependency "rake", ">= 13.0"
end

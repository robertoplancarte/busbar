require_relative "lib/busbar/version"

Gem::Specification.new do |spec|
  spec.name        = "busbar"
  spec.version     = Busbar::VERSION
  spec.authors     = [ "Roberto Plancarte" ]
  spec.homepage    = "https://github.com/robertoplancarte/busbar"
  spec.summary     = "A mountable Rails engine for onboarding client data from CSV and other files."
  spec.description = "BusBar loads client CSV, TSV, XLSX, JSON and NDJSON files of any record type into a " \
                     "host Rails app, from in-app uploads, SFTP, buckets, email or HTTPS push, once or on a recurring feed."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  # Private until the open-source question in docs/spec.md is settled.
  spec.metadata["allowed_push_host"] = "https://rubygems.pkg.github.com/robertoplancarte"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "pg", ">= 1.5"
  spec.add_dependency "acts_as_tenant", ">= 1.0"
  spec.add_dependency "statesman", ">= 12.0"
  spec.add_dependency "turbo-rails", ">= 2.0"
  spec.add_dependency "stimulus-rails", ">= 1.3"
  spec.add_dependency "csv", ">= 3.2"
  spec.add_dependency "roo", ">= 2.10"
end

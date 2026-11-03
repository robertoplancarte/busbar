source "https://rubygems.org"

# Specify your gem's dependencies in busbar.gemspec.
gemspec

gem "puma"
gem "propshaft"

group :development, :test do
  gem "bcrypt", "~> 3.1.7" # the dummy app's User uses has_secure_password, like locke
  gem "rspec-rails", "~> 8.0"
  gem "debug", ">= 1.0.0"
end

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

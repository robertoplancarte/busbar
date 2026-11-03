require "active_job/railtie"
require "active_storage/engine"
require "acts_as_tenant"
require "statesman"
require "turbo-rails"
require "stimulus-rails"

module Busbar
  class Engine < ::Rails::Engine
    isolate_namespace Busbar

    config.generators do |g|
      g.test_framework :rspec
      g.orm :active_record, primary_key_type: :bigint
    end

    initializer "busbar.statesman" do
      Statesman.configure { storage_adapter(Statesman::Adapters::ActiveRecord) }
    end

    # Extension gems (busbar-oneroster, ...) hook in with
    # ActiveSupport.on_load(:busbar), so adding them to a Gemfile is the whole
    # install. The hook fires once the host has finished initializing.
    config.after_initialize do
      ActiveSupport.run_load_hooks(:busbar, Busbar)
    end
  end
end

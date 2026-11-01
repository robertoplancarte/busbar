require "busbar/version"
require "busbar/configuration"
require "busbar/engine"

# BusBar loads client data files into a host Rails app. See docs/spec.md.
module Busbar
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class << self
    def config
      @config ||= Configuration.new
    end

    # Busbar.configure { |c| c.tenant_class = "Account" }
    def configure
      yield config
      config
    end

    def reset_config!
      @config = nil
    end

    def tenant_class
      config.tenant_class.constantize
    end
  end
end

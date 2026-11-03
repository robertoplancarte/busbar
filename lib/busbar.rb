require "csv"
require "json"
require "digest"
require "securerandom"
require "busbar/version"

module Busbar
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class NotAuthorized < Error; end
  class MissingTenant < Error; end
end

require "busbar/configuration"
require "busbar/registry"
require "busbar/types"
require "busbar/validators"
require "busbar/transforms"
require "busbar/schema"
require "busbar/loader"
require "busbar/loaders/active_record"
require "busbar/loaders/active_record_save"
require "busbar/after_ingestion"
require "busbar/parsers"
require "busbar/suggesters"
require "busbar/install_check"
require "busbar/engine"

# BusBar loads client data files into a host Rails app. See docs/spec.md.
module Busbar
  class << self
    def config
      @config ||= Configuration.new
    end

    # Busbar.configure { |c| c.tenant_class = "Tenant" }
    def configure
      yield config
      config
    end

    def reset_config!
      @config = nil
    end

    def tenant_class
      name = config.tenant_class or raise ConfigurationError, "Set Busbar.config.tenant_class (e.g. \"Tenant\") in config/initializers/busbar.rb"
      name.constantize
    end

    def tenant_column
      config.tenant_column or raise ConfigurationError, "Set Busbar.config.tenant_class in config/initializers/busbar.rb"
    end

    # Calls the host's authorize callable. Denies when the host has not set one.
    def authorized?(user, action, record)
      config.authorize ? !!config.authorize.call(user, action, record) : false
    end

    # -- Step library -------------------------------------------------------

    def types = @types ||= Registry.new("type", Types::BUILT_IN)
    def validators = @validators ||= Registry.new("validator", Validators::BUILT_IN)
    def transforms = @transforms ||= Registry.new("transform", Transforms::BUILT_IN)

    def register_type(name, klass) = types.register(name, klass)
    def register_validator(name, klass) = validators.register(name, klass)
    def register_transform(name, klass) = transforms.register(name, klass)

    # -- Schemas --------------------------------------------------------------

    def schemas
      @schemas ||= begin
        require "busbar/schemas/user"
        Registry.new("schema", "user" => Schemas.user)
      end
    end

    # Defines (or replaces) a code schema. See Busbar::Schema::Builder.
    def define_schema(key, &block)
      schemas.register(key, Schema.build(key, &block))
    end

    def schema(key) = schemas.fetch(key)

    # -- Loaders --------------------------------------------------------------

    # Custom loader for one schema; wins over the schema's own `loader` line.
    def register_loader(schema_key, klass) = loaders.register(schema_key, klass)

    def loaders = @loaders ||= Registry.new("loader", {})

    def loader_for(schema)
      klass = loaders[schema.key] || Loader.resolve(schema.loader_kind)
      klass.new(schema)
    end

    # -- After ingestion ------------------------------------------------------

    def after_ingestion_for(schema_key)
      handlers = config.after_ingestion.to_h.stringify_keys
      name = handlers[schema_key.to_s] || handlers["default"]
      name ? name.to_s.constantize.new : AfterIngestion.new
    end

    # Clears registries; for tests.
    def reset_registries!
      @types = @validators = @transforms = @schemas = @loaders = nil
    end
  end
end

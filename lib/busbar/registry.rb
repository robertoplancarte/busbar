module Busbar
  # A name -> object table for types, validators, transforms, schemas and
  # loaders. Names are strings so JSON templates and Ruby agree.
  class Registry
    include Enumerable

    def initialize(kind, entries)
      @kind = kind
      @entries = entries.transform_keys(&:to_s)
    end

    def register(name, object)
      @entries[name.to_s] = object
    end

    def [](name) = @entries[name.to_s]

    def fetch(name)
      @entries.fetch(name.to_s) { raise ConfigurationError, "Unknown #{@kind} #{name.inspect}" }
    end

    def key?(name) = @entries.key?(name.to_s)
    def keys = @entries.keys
    def each(&) = @entries.each(&)
  end
end

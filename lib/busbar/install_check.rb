module Busbar
  # Checks every registered schema against the host app: the model exists,
  # carries the tenant column, has a unique index the upsert loader can use,
  # and does not depend on model code the upsert loader would skip.
  #
  #   bin/rails busbar:check
  class InstallCheck
    Finding = Struct.new(:level, :schema, :message, keyword_init: true) do
      def to_s = "[#{level}] #{schema}: #{message}"
    end

    def self.run(schemas = Busbar.schemas.map(&:last)) = new.run(schemas)

    def run(schemas)
      findings = []
      findings << error("config", "Busbar.config.tenant_class is not set") unless Busbar.config.tenant_class
      schemas.each { |schema| check(schema, findings) } if Busbar.config.tenant_class
      findings
    end

    private

    def check(schema, findings)
      loader = Busbar.loader_for(schema)
      model = loader.model
      tenant_column = Busbar.tenant_column.to_s
      unless model.column_names.include?(tenant_column)
        findings << error(schema.key, "#{model.name} has no #{tenant_column} column")
      end

      schema.loadable_fields.each do |field|
        attr = loader.attribute_for(field)
        next if model.attribute_names.include?(attr) || model.method_defined?("#{attr}=")

        findings << warning(schema.key, "field #{field} has no #{model.name}##{attr}; templates must not map it")
      end

      return unless loader.is_a?(Loaders::ActiveRecord)

      schema.natural_keys.each do |key|
        columns = [ tenant_column, *key.map { |f| loader.attribute_for(f) } ]
        next if unique_index?(model, columns)

        findings << error(schema.key, "#{model.table_name} needs a unique index on (#{columns.join(", ")}) for upsert_all")
      end
      model_code(model).each do |what|
        findings << warning(schema.key, "#{model.name} uses #{what}, which the upsert loader skips; " \
                                        "use `loader :active_record_save` for this schema")
      end
    rescue NameError => e
      findings << error(schema.key, e.message)
    end

    def model_code(model)
      found = []
      found << "encrypts (#{model.encrypted_attributes.to_a.join(", ")})" if model.respond_to?(:encrypted_attributes) && model.encrypted_attributes.present?
      found << "has_secure_password" if model.ancestors.any? { |m| m.is_a?(ActiveModel::SecurePassword::InstanceMethodsOnActivation) }
      found << "create callbacks" if create_callbacks?(model)
      found
    end

    # Callbacks the host wrote on create, save or validation (locke's fill
    # otp_secret, webauthn_id and public_id), told apart from the ones Rails
    # and gems such as acts_as_tenant add by where they are defined.
    def create_callbacks?(model)
      %i[_create_callbacks _save_callbacks _validation_callbacks].any? do |chain|
        model.public_send(chain).any? { |cb| host_code?(callback_location(model, cb.filter)) }
      end
    end

    def callback_location(model, filter)
      case filter
      when Symbol, String then model.instance_method(filter).source_location&.first
      when Proc, Method then filter.source_location&.first
      end
    rescue NameError
      nil
    end

    def host_code?(path)
      return false if path.nil?

      library_dirs = Gem.path.map { |p| File.join(p, "gems") } + [ RbConfig::CONFIG["rubylibdir"], File.expand_path("..", __dir__) ]
      library_dirs.none? { |dir| path.start_with?(dir) }
    end

    def unique_index?(model, columns)
      model.connection.indexes(model.table_name).any? do |index|
        index.unique && Array(index.columns).map(&:to_s) == columns
      end
    end

    def error(schema, message) = Finding.new(level: :error, schema: schema, message: message)
    def warning(schema, message) = Finding.new(level: :warning, schema: schema, message: message)
  end
end

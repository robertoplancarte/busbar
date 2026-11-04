module Busbar
  # What a record must look like: fields with types and validators, the
  # natural key that identifies a record, row rules, schema-level transforms
  # and the loader that writes records. Built from Ruby (Busbar.define_schema)
  # or JSON (Schema.from_h), and the same in both cases.
  #
  # Schema#process is the whole per-record path (transforms, casting,
  # validation) with no file, staging or run involved, so it serves
  # ValidateChunkJob today and a record-level entry point (SSO just-in-time
  # creation, SCIM) later.
  class Schema
    # Field names a schema may never declare: passwords are never imported.
    FORBIDDEN_FIELDS = /\A(password|password_digest|encrypted_password|password_confirmation)\z/

    Field = Struct.new(:name, :type, :required, :synonyms, :virtual, :references, :options, keyword_init: true) do
      def label = name.humanize
    end

    Result = Struct.new(:data, :errors, keyword_init: true) do
      def valid? = errors.empty?
    end

    attr_reader :key, :name, :fields, :natural_keys, :loader_kind, :loader_options, :rules, :transforms, :scope_key

    def self.build(key, &block)
      builder = Builder.new(key)
      builder.instance_eval(&block) if block
      builder.to_schema
    end

    # {"key" => "employee", "natural_key" => ["external_id"], "loader" => "active_record:Employee", "fields" => [...]}
    def self.from_h(hash)
      hash = hash.deep_stringify_keys
      build(hash.fetch("key")) do
        name hash["name"] if hash["name"]
        Array(hash["natural_keys"] || [ hash["natural_key"] ]).compact.each { |nk| natural_key(*Array(nk)) }
        kind, model = hash.fetch("loader", "active_record").split(":", 2)
        loader kind, model: model || hash.dig("loader_options", "model"), **hash.fetch("loader_options", {}).except("model").symbolize_keys
        hash.fetch("fields").each do |f|
          field f.fetch("name"), f.fetch("type", "string"), **f.except("name", "type").symbolize_keys
        end
        Array(hash["rules"]).each { |r| rule r.fetch("validator"), **r.fetch("args", {}).symbolize_keys }
        Array(hash["transforms"]).each { |t| transform t.fetch("field"), t.fetch("step"), **t.fetch("args", {}).symbolize_keys }
      end
    end

    def initialize(key:, name:, fields:, natural_keys:, loader_kind:, loader_options:, rules:, transforms:, scope_key: nil)
      @key = key.to_s
      @name = name || @key.humanize
      @fields = fields.index_by(&:name)
      @natural_keys = natural_keys
      @loader_kind = loader_kind.to_s
      @loader_options = loader_options
      @rules = rules
      @transforms = transforms
      @scope_key = scope_key
      validate!
    end

    def field(name) = fields[name.to_s]
    def field_names = fields.keys

    # Fields the loader writes to the host model; virtual fields only feed
    # transforms (first_name + last_name -> name) and are never written.
    def loadable_fields = fields.values.reject(&:virtual).map(&:name)

    def model_name = loader_options[:model]

    # The natural key a template uses: its explicit choice, or the first
    # candidate whose fields are all mapped. For the user schema that is
    # external_id when the client's file has one, otherwise email.
    def natural_key_for(mapped_fields, explicit = nil)
      return Array(explicit).map(&:to_s) if explicit.present?

      mapped = mapped_fields.map(&:to_s)
      natural_keys.find { |candidate| (candidate - mapped).empty? } || natural_keys.first
    end

    def required_fields = fields.values.select(&:required).map(&:name)

    # Runs template transforms, schema transforms, casting, field validators
    # and row rules over one record. `input` is field name => raw value.
    def process(input, template_transforms: [], value_maps: {})
      data = input.to_h.transform_keys(&:to_s).slice(*field_names)
      apply_transforms(data, template_transforms, value_maps)
      apply_transforms(data, transforms, value_maps)
      errors = []
      fields.each_value { |f| cast_and_validate(f, data, errors) }
      errors.concat(rule_errors(data)) if errors.empty?
      Result.new(data: data, errors: errors)
    end

    def as_json(*)
      {
        "key" => key, "name" => name, "natural_keys" => natural_keys,
        "loader" => [ loader_kind, model_name ].compact.join(":"),
        "fields" => fields.values.map { |f| f.to_h.compact.transform_keys(&:to_s) },
        "rules" => rules, "transforms" => transforms
      }
    end

    private

    def validate!
      bad = field_names.grep(FORBIDDEN_FIELDS)
      raise ConfigurationError, "Schema #{key} declares #{bad.join(", ")}: BusBar never imports passwords" if bad.any?
      raise ConfigurationError, "Schema #{key} needs a natural_key" if natural_keys.empty?

      unknown = natural_keys.flatten - field_names
      raise ConfigurationError, "Schema #{key} natural key uses unknown fields #{unknown.join(", ")}" if unknown.any?
    end

    def apply_transforms(data, steps, value_maps)
      Array(steps).each do |step|
        step = step.to_h.stringify_keys
        field = step.fetch("field").to_s
        args = step.fetch("args", {}).to_h.deep_symbolize_keys
        ctx = Transforms::Context.new(data: data, value_maps: value_maps, field: field)
        data[field] = Busbar.transforms.fetch(step.fetch("step")).call(data[field], args, ctx)
      end
    end

    def cast_and_validate(field, data, errors)
      value = data[field.name]
      value = nil if value.is_a?(::String) && value.strip.empty?
      if value.nil?
        data[field.name] = nil
        errors << error(field.name, "is required", "required") if field.required
        return
      end

      data[field.name] = value = Busbar.types.fetch(field.type).cast(value, field)
      field.options.fetch(:validators, {}).each do |name, args|
        message = Busbar.validators.fetch(name).call(value, (args.is_a?(Hash) ? args.symbolize_keys : args), field)
        errors << error(field.name, message, name) if message
      end
    rescue Types::Invalid => e
      errors << error(field.name, e.message, field.type)
    end

    def rule_errors(data)
      rules.flat_map do |rule|
        Busbar.validators.fetch(rule[:validator]).call(data, rule[:args]).map do |field, message|
          error(field, message, rule[:validator])
        end
      end
    end

    def error(field, message, validator) = { "field" => field.to_s, "message" => message, "validator" => validator.to_s }

    # The Ruby DSL. See Busbar.define_schema.
    class Builder
      FIELD_KEYS = %i[required synonyms virtual references].freeze
      VALIDATOR_OPTIONS = %i[format length range].freeze

      def initialize(key)
        @key = key
        @fields = []
        @natural_keys = []
        @rules = []
        @transforms = []
        @loader_kind = "active_record"
        @loader_options = {}
      end

      def name(value) = @name = value

      # Call more than once to list candidates, best first; templates pick
      # the first one whose fields their file has.
      def natural_key(*fields) = @natural_keys << fields.flatten.map(&:to_s)

      def scope_key(field) = @scope_key = field.to_s

      # loader :active_record, model: "Employee" (upsert_all, fast)
      # loader :active_record_save, model: "User" (save per row, callbacks run)
      def loader(kind, **options) = (@loader_kind, @loader_options = kind, options.symbolize_keys)

      def field(name, type = :string, **options)
        options = options.symbolize_keys
        validators = options.delete(:validators).to_h.stringify_keys
        VALIDATOR_OPTIONS.each { |v| validators[v.to_s] = options.delete(v) if options.key?(v) }
        validators["enum"] = { values: options[:values] } if type.to_s == "enum" && options[:values]
        attrs = options.extract!(*FIELD_KEYS)
        @fields << Field.new(
          name: name.to_s, type: type.to_s, required: !!attrs[:required], synonyms: Array(attrs[:synonyms]),
          virtual: !!attrs[:virtual], references: attrs[:references],
          options: options.merge(validators: validators.except("enum").compact)
        )
      end

      def rule(validator, **args) = @rules << { validator: validator.to_s, args: args }

      # Schema-level transform, applied after the template's own.
      def transform(field, step, **args) = @transforms << { "field" => field.to_s, "step" => step.to_s, "args" => args }

      def to_schema
        Schema.new(key: @key, name: @name, fields: @fields, natural_keys: @natural_keys,
                   loader_kind: @loader_kind, loader_options: @loader_options,
                   rules: @rules, transforms: @transforms, scope_key: @scope_key)
      end
    end
  end
end

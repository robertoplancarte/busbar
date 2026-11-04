module Busbar
  # Loaders are the only code that writes host records. A loader is built per
  # schema and gets batches of validated rows plus a Context.
  #
  #   class EmployeeLoader < Busbar::Loader
  #     def load(rows, context)
  #       ...                         # write rows, return outcomes (see Outcome)
  #     end
  #   end
  #   Busbar.register_loader :employee, EmployeeLoader
  #
  # The base class finds records through the host model (`where(key => ...)`),
  # never by joining raw column values in SQL, so natural keys stored with
  # Active Record encryption (deterministic) or `normalizes` match the way the
  # model itself would match them.
  class Loader
    # tenant: the host tenant record; run: the Busbar::Run (nil for a single
    # record); natural_key: the field names identifying a record.
    Context = Struct.new(:tenant, :run, :load_mode, :natural_key, :user, keyword_init: true) do
      def tenant_column = Busbar.tenant_column
    end

    # One validated row on its way to the loader. `key` is the natural key
    # values in natural_key order; `data` is field => value for every field
    # the template mapped (virtual fields removed).
    Row = Struct.new(:id, :row_number, :key, :data, :action, keyword_init: true) do
      def to_h = data
    end

    # What happened to one row. status: :created, :updated, :unchanged,
    # :skipped or :failed. errors use the same shape as validator errors.
    Outcome = Struct.new(:status, :record, :record_id, :errors, keyword_init: true) do
      def failed? = status == :failed
    end

    KINDS = {}

    def self.register_kind(name, klass) = KINDS[name.to_s] = klass

    def self.resolve(kind)
      KINDS.fetch(kind.to_s) { Busbar.loaders[kind] || raise(ConfigurationError, "Unknown loader #{kind.inspect}") }
    end

    attr_reader :schema

    def initialize(schema)
      @schema = schema
    end

    def model
      name = schema.model_name or raise ConfigurationError, "Schema #{schema.key} has no model; use loader :active_record, model: \"...\""
      name.constantize
    end

    # field name -> model attribute, from the schema's loader attribute_map.
    def attribute_for(field) = schema.loader_options.fetch(:attribute_map, {}).to_h.stringify_keys.fetch(field.to_s, field.to_s)

    def attributes_for(data) = data.to_h.transform_keys { |f| attribute_for(f) }

    # rows: Array<Row>. Returns { row.id => Outcome }.
    def load(_rows, _context) = raise(NotImplementedError, "#{self.class} must implement load(rows, context)")

    # Called with the natural keys of records missing from a snapshot_deactivate
    # file. What deactivating means is the host's call (a status, revoking
    # sessions, ...), so there is no default. `records_for(keys, context)`
    # finds the records.
    def deactivate(_keys, _context)
      raise NotImplementedError, "#{self.class} must implement deactivate(keys, context) to use snapshot_deactivate"
    end

    def delete(keys, context) = records_for(keys, context).destroy_all

    # The tenant's records, through the model so its default scopes and
    # acts_as_tenant apply.
    def scope(context)
      relation = model.all
      relation = relation.where(context.tenant_column => context.tenant.id) if model.column_names.include?(context.tenant_column.to_s)
      relation
    end

    # { key_string => record } for the given natural keys (arrays of values),
    # keyed by Loader.key_string of each key as given. Values go through the
    # model's `normalizes`, so "ANA@acme.test" finds ana@acme.test.
    def find_existing(keys, context)
      keys = keys.uniq
      return {} if keys.empty?

      fields = context.natural_key
      normalized = keys.to_h { |k| [ self.class.key_string(normalize_key(k, fields)), self.class.key_string(k) ] }
      conditions = fields.each_with_index.to_h { |f, i| [ attribute_for(f), keys.map { |k| k[i] }.uniq ] }
      in_tenant(context) do
        scope(context).where(conditions).each_with_object({}) do |record, found|
          given = normalized[self.class.key_string(key_of(record, fields))]
          found[given] = record if given
        end
      end
    end

    def records_for(keys, context)
      ids = find_existing(keys, context).values.map(&:id)
      scope(context).where(model.primary_key => ids)
    end

    # Every natural key the tenant has, for snapshot modes. Uses pluck, which
    # decrypts encrypted attributes.
    def existing_keys(context)
      attrs = context.natural_key.map { |f| attribute_for(f) }
      in_tenant(context) { scope(context).pluck(*attrs).map { |values| Array(values) } }
    end

    def normalize_key(values, fields)
      fields.each_with_index.map do |f, i|
        attr = attribute_for(f)
        model.respond_to?(:normalize_value_for) ? model.normalize_value_for(attr, values[i]) : values[i]
      end
    end

    def key_of(record, fields) = fields.map { |f| record.public_send(attribute_for(f)) }

    # True when saving `data` onto `record` would change nothing. Values are
    # cast and normalized through the model, as assigning them would.
    def unchanged?(record, data)
      attributes_for(data).all? do |attr, value|
        next true unless record.has_attribute?(attr)

        cast = record.class.type_for_attribute(attr).cast(value)
        cast = record.class.normalize_value_for(attr, cast) if record.class.respond_to?(:normalize_value_for)
        record.public_send(attr) == cast
      end
    end

    # Normalized key for hashing and comparing: strings, case kept.
    def self.key_string(values) = Array(values).map { |v| v.nil? ? "" : v.to_s }.to_json

    def self.digest(values) = Digest::SHA256.hexdigest(key_string(values))

    private

    def in_tenant(context, &) = ActsAsTenant.with_tenant(context.tenant, &)

    def model_errors(record)
      reverse = schema.loader_options.fetch(:attribute_map, {}).to_h.stringify_keys.invert
      record.errors.map do |e|
        field = reverse.fetch(e.attribute.to_s, e.attribute.to_s)
        { "field" => field, "message" => e.message, "validator" => "model" }
      end
    end
  end
end

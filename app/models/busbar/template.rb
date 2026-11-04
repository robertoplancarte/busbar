module Busbar
  # One client's confirmed mapping from their file to a schema. Plain JSON,
  # so it can be stored, versioned and diffed. Each edit bumps `version`, and
  # each run keeps a snapshot of the template it used.
  class Template < ApplicationRecord
    self.table_name = "busbar_templates"
    busbar_tenant_scoped

    LOAD_MODES = %w[incremental create_only snapshot_deactivate snapshot_delete].freeze

    has_many :runs, class_name: "Busbar::Run", dependent: :nullify

    validates :name, :schema_key, presence: true
    validates :load_mode, inclusion: { in: LOAD_MODES }
    validate :maps_known_fields

    before_update { self.version += 1 if (changed & %w[column_map transforms value_maps options load_mode natural_key]).any? }

    def schema = Busbar.schema(schema_key)

    def mapped_fields = column_map.to_h.values.compact_blank.uniq

    def effective_natural_key = schema.natural_key_for(mapped_fields, natural_key)

    def snapshot
      attributes.slice("id", "version", "name", "schema_key", "column_map", "transforms", "value_maps",
                       "options", "load_mode").merge("natural_key" => effective_natural_key)
    end

    private

    def maps_known_fields
      return unless Busbar.schemas.key?(schema_key)

      unknown = mapped_fields - schema.field_names
      errors.add(:column_map, "maps to unknown fields #{unknown.join(", ")}") if unknown.any?
      missing = schema.required_fields - mapped_fields
      errors.add(:column_map, "leaves required fields unmapped: #{missing.join(", ")}") if missing.any?
      dupes = column_map.to_h.values.compact_blank.tally.select { |_, n| n > 1 }.keys
      errors.add(:column_map, "maps more than one column to #{dupes.join(", ")}") if dupes.any?
      keys = effective_natural_key - mapped_fields
      errors.add(:natural_key, "uses fields the file does not have: #{keys.join(", ")}") if keys.any?
    end
  end
end

module Busbar
  module Loaders
    # The fast path: one upsert_all per batch on the (tenant column + natural
    # key) unique index. It writes the tenant column itself, because
    # upsert_all bypasses acts_as_tenant, and it skips model validations,
    # callbacks and Active Record encryption. InstallCheck warns when a
    # schema points it at a model that relies on those; use
    # Loaders::ActiveRecordSave there.
    #
    #   loader :active_record, model: "Employee"
    class ActiveRecord < Loader
      def load(rows, context)
        return {} if rows.empty?

        writable = rows.reject { |r| r.action.to_s == "skip" }
        if writable.any?
          tenant_column = context.tenant_column.to_s
          records = writable.map { |r| attributes_for(r.data).merge(tenant_column => context.tenant.id) }
          model.upsert_all(records, unique_by: unique_by(context), record_timestamps: true)
        end
        existing = find_existing(rows.map(&:key), context)
        rows.to_h do |row|
          record = existing[self.class.key_string(row.key)]
          status = row.action.to_s == "skip" ? :skipped : (row.action.to_s == "create" ? :created : :updated)
          [ row.id, Outcome.new(status: record ? status : :failed, record: record, record_id: record&.id,
                                errors: record ? [] : [ { "field" => "base", "message" => "was not saved", "validator" => "loader" } ]) ]
        end
      end

      def unique_by(context)
        [ context.tenant_column.to_s, *context.natural_key.map { |f| attribute_for(f) } ].map(&:to_sym)
      end
    end

    Loader.register_kind :active_record, ActiveRecord
  end
end

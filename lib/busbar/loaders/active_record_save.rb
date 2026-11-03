module Busbar
  module Loaders
    # Saves one record per row through the host model: validations,
    # callbacks, `normalizes`, has_secure_password and Active Record
    # encryption all run, exactly as when the host app saves a record itself.
    # Slower than the upsert loader, so it is meant for models with business
    # logic, such as users.
    #
    #   loader :active_record_save, model: "User"
    #
    # A model validation error lands on the staged row as a row error, the
    # same shape as BusBar's own validators, and the rest of the batch goes on.
    #
    # Hooks for subclasses:
    #   initial_password(record, row, context)  -> String for new records
    #   before_save(record, row, context)       -> anything else to set
    class ActiveRecordSave < Loader
      def load(rows, context)
        existing = find_existing(rows.map(&:key), context)
        rows.to_h { |row| [ row.id, save_row(row, existing[self.class.key_string(row.key)], context) ] }
      end

      # The single-record path: finds by natural key, then saves. Reused by
      # load, and the entry point a later Busbar.ingest_record (SSO
      # just-in-time creation, SCIM) calls with one row.
      def load_record(row, context, record: :find)
        record = find_existing([ row.key ], context).values.first if record == :find
        save_row(row, record, context)
      end

      # Random, never shown and never imported. Users set their own through
      # the host's invitation or password reset flow.
      def initial_password(_record, _row, _context) = SecureRandom.base58(32)

      def before_save(_record, _row, _context) = nil

      private

      def save_row(row, record, context)
        return Outcome.new(status: :skipped, record: record, record_id: record.id, errors: []) if record && context.load_mode.to_s == "create_only"

        ActsAsTenant.with_tenant(context.tenant) do
          new_record = record.nil?
          record ||= build(context)
          record.assign_attributes(attributes_for(row.data))
          set_password(record, row, context) if new_record
          before_save(record, row, context)
          return Outcome.new(status: :unchanged, record: record, record_id: record.id, errors: []) unless new_record || record.changed?

          saved = model.transaction(requires_new: true) { record.save || raise(::ActiveRecord::Rollback) }
          if saved
            Outcome.new(status: new_record ? :created : :updated, record: record, record_id: record.id, errors: [])
          else
            Outcome.new(status: :failed, record: record, record_id: record.id, errors: model_errors(record))
          end
        end
      rescue ::ActiveRecord::ActiveRecordError, ActiveModel::UnknownAttributeError => e
        Outcome.new(status: :failed, record: record, record_id: record&.id,
                    errors: [ { "field" => "base", "message" => e.message, "validator" => "model" } ])
      end

      def build(context)
        record = model.new
        column = context.tenant_column.to_s
        record[column] = context.tenant.id if record.has_attribute?(column)
        record
      end

      def set_password(record, row, context)
        return unless record.respond_to?(:password=)

        record.password = initial_password(record, row, context)
      end
    end

    Loader.register_kind :active_record_save, ActiveRecordSave
  end
end

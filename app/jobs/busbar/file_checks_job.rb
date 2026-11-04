module Busbar
  # Checks that need the whole file, set-based over staged rows: duplicate
  # natural keys, and references to rows in the file or records already in
  # the tenant.
  class FileChecksJob < ApplicationJob
    def perform(run_id)
      run = find_run(run_id)
      return unless run.in_state?(:validating)

      mark_duplicates(run)
      check_references(run)
      DiffJob.perform_later(run.id)
    end

    private

    # Every row after the first with the same natural key is invalid.
    def mark_duplicates(run)
      StagedRow.connection.execute(StagedRow.sanitize_sql([ <<~SQL, { run_id: run.id, field: run.natural_key.join("+") } ]))
        WITH firsts AS (
          SELECT id, natural_key_digest,
                 MIN(row_number) OVER (PARTITION BY natural_key_digest) AS first_row
          FROM busbar_staged_rows
          WHERE run_id = :run_id AND status = 'valid'
        )
        UPDATE busbar_staged_rows s
        SET status = 'invalid',
            row_errors = s.row_errors || jsonb_build_array(jsonb_build_object(
              'field', :field, 'validator', 'unique_in_file',
              'message', 'duplicates row ' || firsts.first_row))
        FROM firsts
        WHERE s.id = firsts.id AND s.row_number <> firsts.first_row
      SQL
    end

    # Fields with references: { schema: "user", field: "email" } (or just the
    # schema key, meaning its first natural key field).
    def check_references(run)
      run.schema.fields.each_value do |field|
        next unless field.references && run.column_map.value?(field.name)

        target_schema, target_field = reference_target(field.references)
        values = run.staged_rows.where(status: "valid").where("data ->> ? IS NOT NULL", field.name).distinct.pluck(Arel.sql(StagedRow.sanitize_sql([ "data ->> ?", field.name ])))
        next if values.empty?

        known = Set.new
        known.merge(run.staged_rows.where(status: "valid").pluck(Arel.sql(StagedRow.sanitize_sql([ "data ->> ?", target_field ])))) if target_schema.key == run.schema.key
        loader = Busbar.loader_for(target_schema)
        context = Loader::Context.new(tenant: run.tenant, natural_key: [ target_field ])
        known.merge(loader.find_existing(values.map { |v| [ v ] }, context).keys.map { |k| JSON.parse(k).first })
        missing = values - known.to_a
        next if missing.empty?

        run.staged_rows.where(status: "valid").where("data ->> ? IN (?)", field.name, missing).find_each do |row|
          row.update_columns(status: "invalid", row_errors: row.row_errors + [
            { "field" => field.name, "message" => "does not match any #{target_schema.name.downcase} #{target_field}", "validator" => "references" }
          ])
        end
      end
    end

    def reference_target(ref)
      ref = ref.is_a?(Hash) ? ref.stringify_keys : { "schema" => ref.to_s }
      schema = Busbar.schema(ref.fetch("schema"))
      [ schema, (ref["field"] || schema.natural_keys.first.first).to_s ]
    end
  end
end

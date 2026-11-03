module Busbar
  # Transforms, casting, field validators and row rules for one chunk,
  # written back in one statement. The last chunk to finish enqueues
  # FileChecksJob.
  class ValidateChunkJob < ApplicationJob
    def perform(run_id, chunk)
      run = find_run(run_id)
      return unless run.in_state?(:validating)

      schema = run.schema
      natural_key = run.natural_key
      rows = run.staged_rows.where(chunk: chunk).order(:row_number).map do |row|
        result = schema.process(row.data, template_transforms: run.template_transforms, value_maps: run.value_maps)
        key = natural_key.map { |f| result.data[f] }
        errors = result.errors
        errors += [ { "field" => natural_key.join("+"), "message" => "is required to identify the record", "validator" => "natural_key" } ] if errors.empty? && key.any?(&:nil?)
        row.attributes.except("handled_at").merge(
          "data" => result.data.as_json, "natural_key" => key.as_json,
          "natural_key_digest" => Loader.digest(key), "row_errors" => errors,
          "status" => errors.empty? ? "valid" : "invalid", "action" => nil
        )
      end
      StagedRow.upsert_all(rows, unique_by: :id, record_timestamps: false) if rows.any?

      done = run.increment_chunks_done!
      FileChecksJob.perform_later(run.id) if done >= run.chunk_count && run.claim!(:checks_enqueued_at)
    end
  end
end

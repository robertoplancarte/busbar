module Busbar
  # Sends one chunk's valid rows to the loader in batches and records each
  # row's outcome. Invalid rows never reach the loader. A batch that keeps
  # raising is retried, then its rows are marked failed and the run goes on.
  class LoadChunkJob < ApplicationJob
    ATTEMPTS = 3

    retry_on StandardError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      job.send(:give_up, error)
    end

    def perform(run_id, chunk)
      run = find_run(run_id)
      return unless run.in_state?(:loading)

      loader = run.loader
      context = run.loader_context
      pending = run.staged_rows.where(chunk: chunk, status: "valid")
      pending.where(action: %w[unchanged skip]).update_all(status: "loaded")
      pending.where(action: %w[create update]).in_batches(of: Busbar.config.load_batch_size) do |batch|
        rows = batch.order(:row_number).to_a
        outcomes = loader.load(rows.map { |r| loader_row(run, r) }, context)
        rows.each { |row| record_outcome(row, outcomes[row.id]) }
      end
      Runs.advance_after_load(run)
    end

    private

    def loader_row(run, row)
      Loader::Row.new(id: row.id, row_number: row.row_number, key: row.natural_key_values,
                      data: run.loadable_data(row.data), action: row.action)
    end

    def record_outcome(row, outcome)
      if outcome.nil? || outcome.failed?
        errors = outcome&.errors.presence || [ { "field" => "base", "message" => "was not loaded", "validator" => "loader" } ]
        row.update_columns(status: "failed", row_errors: row.row_errors + errors, record_id: outcome&.record_id)
      else
        action = { created: "create", updated: "update", unchanged: "unchanged", skipped: "skip" }.fetch(outcome.status)
        row.update_columns(status: "loaded", action: action, record_id: outcome.record_id)
      end
    end

    def give_up(error)
      run_id, chunk = arguments
      ActsAsTenant.with_tenant(ActsAsTenant.without_tenant { Busbar.tenant_class.find(tenant_id) }) do
        run = Run.find(run_id)
        run.staged_rows.where(chunk: chunk, status: "valid").find_each do |row|
          row.update_columns(status: "failed", row_errors: row.row_errors + [
            { "field" => "base", "message" => "#{error.class}: #{error.message}".truncate(500), "validator" => "loader" }
          ])
        end
        Runs.advance_after_load(run)
      end
    end
  end
end

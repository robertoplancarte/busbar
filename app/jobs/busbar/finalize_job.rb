module Busbar
  # Snapshot deactivation or deletion, totals, the error CSV, the final
  # state, the completion event, and then the host's after-ingestion handler.
  class FinalizeJob < ApplicationJob
    def perform(run_id)
      run = find_run(run_id)
      return unless run.in_state?(:loading)

      apply_snapshot(run)
      totals = run.staged_rows.group(:status, :action).count
      count = ->(status, action = nil) { totals.sum { |(s, a), n| s == status && (action.nil? || a == action) ? n : 0 } }
      run.update!(
        created_count: count.("loaded", "create"), updated_count: count.("loaded", "update"),
        unchanged_count: count.("loaded", "unchanged"), skipped_count: count.("loaded", "skip"),
        invalid_count: count.("invalid"), failed_count: count.("failed"), finished_at: Time.current
      )
      ErrorFile.attach(run) if run.invalid_count + run.failed_count > 0
      run.transition_to!(run.failed_count + run.invalid_count > 0 ? :completed_with_errors : :completed)
      ActiveSupport::Notifications.instrument("run.completed.busbar", run: run)
      AfterIngestionJob.perform_later(run.id)
    end

    private

    # Records missing from a snapshot file go to the loader's deactivate (or,
    # with snapshot_delete, delete). The host decides what deactivating means.
    def apply_snapshot(run)
      return unless run.load_mode.start_with?("snapshot_")

      in_file = run.staged_rows.where.not(natural_key: nil).pluck(:natural_key).map { |k| Loader.key_string(k) }.to_set
      missing = run.loader.existing_keys(run.loader_context).reject { |k| in_file.include?(Loader.key_string(k)) }
      return if missing.empty?

      run.load_mode == "snapshot_delete" ? run.loader.delete(missing, run.loader_context) : run.loader.deactivate(missing, run.loader_context)
      run.update!(deactivated_keys: missing)
    end
  end
end

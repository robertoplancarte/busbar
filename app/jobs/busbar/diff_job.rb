module Busbar
  # Labels each valid row create, update, unchanged or skip by finding the
  # existing records through the loader, which asks the host model
  # (`where(email: [...])`). That is what makes natural keys stored with
  # deterministic Active Record encryption or `normalizes` work: the model
  # encrypts and normalizes the lookup values, where a SQL join on raw
  # columns would compare plaintext with ciphertext.
  class DiffJob < ApplicationJob
    def perform(run_id)
      run = find_run(run_id)
      return unless run.in_state?(:validating)

      loader = run.loader
      context = run.loader_context
      run.staged_rows.where(status: "valid").in_batches(of: Busbar.config.load_batch_size) do |batch|
        rows = batch.to_a
        existing = loader.find_existing(rows.map(&:natural_key_values), context)
        actions = rows.group_by do |row|
          record = existing[Loader.key_string(row.natural_key_values)]
          if record.nil? then "create"
          elsif run.load_mode == "create_only" then "skip"
          elsif loader.unchanged?(record, run.loadable_data(row.data)) then "unchanged"
          else "update"
          end
        end
        actions.each { |action, group| StagedRow.where(id: group.map(&:id)).update_all(action: action) }
      end

      if run.review_required?
        run.transition_to!(:ready)
        ActiveSupport::Notifications.instrument("run.ready.busbar", run: run)
      else
        Runs.start_loading(run)
      end
    end
  end
end

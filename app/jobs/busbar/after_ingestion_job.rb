module Busbar
  # Runs the host's Busbar::AfterIngestion handler for the run's schema in
  # its own job, so a slow or failing handler never blocks or rolls back the
  # load. Safe to re-run: see AfterIngestion::RowSet.
  class AfterIngestionJob < ApplicationJob
    retry_on StandardError, attempts: 3, wait: :polynomially_longer do |job, error|
      job.send(:flag_failed, error)
    end

    def perform(run_id)
      run = find_run(run_id)
      run.update_columns(after_ingestion_state: "running")
      Busbar.after_ingestion_for(run.schema_key).call(run, AfterIngestion::Context.new(run))
      run.update_columns(after_ingestion_state: "done")
    end

    private

    def flag_failed(error)
      ActsAsTenant.with_tenant(ActsAsTenant.without_tenant { Busbar.tenant_class.find(tenant_id) }) do
        run = Run.find(arguments.first)
        run.update_columns(after_ingestion_state: "failed", error: "after ingestion: #{error.class}: #{error.message}".truncate(2_000))
        ActiveSupport::Notifications.instrument("run.after_ingestion_failed.busbar", run: run, error: error)
      end
    end
  end
end

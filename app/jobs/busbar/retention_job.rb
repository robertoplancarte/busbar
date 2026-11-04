module Busbar
  # Deletes raw files, staged rows and error files of runs older than
  # Busbar.config.retention, keeping the run and its counts for audit.
  # Enqueue it daily per tenant from the host's scheduler.
  class RetentionJob < ApplicationJob
    def perform
      Run.where(finished_at: ...Busbar.config.retention.ago).find_each do |run|
        run.staged_rows.delete_all
        run.file.purge_later if run.file.attached?
        run.error_file.purge_later if run.error_file.attached?
      end
    end
  end
end

# Runs a file through the whole pipeline with the test queue adapter.
module PipelineHelpers
  include ActiveJob::TestHelper

  def fixture_file(name) = Rails.root.join("..", "fixtures", "files", name).to_s

  def column_map_for(name, map) = map

  # Uploads `file`, confirms `column_map`, approves the review, and returns
  # the reloaded run. Pass approve: false to stop at review.
  def import(tenant, file, schema: :user, column_map:, natural_key: nil, load_mode: "incremental", approve: true, template: nil)
    run = nil
    perform_enqueued_jobs do
      run = Busbar::Runs.create_from(fixture_file(file), tenant: tenant, schema: schema, template: template)
    end
    ActsAsTenant.with_tenant(tenant) do
      run.reload
      if run.in_state?(:awaiting_mapping)
        perform_enqueued_jobs do
          template = Busbar::Runs.confirm_mapping(run, column_map: column_map, natural_key: natural_key, load_mode: load_mode)
          raise template.errors.full_messages.to_sentence if template.errors.any?
        end
      end
      run.reload
      perform_enqueued_jobs { Busbar::Runs.approve(run) } if approve && run.in_state?(:ready)
      run.reload
    end
  end

  def users_in(tenant) = ActsAsTenant.with_tenant(tenant) { User.order(:id).to_a }

  def rows_of(run) = ActsAsTenant.with_tenant(run.tenant) { run.staged_rows.order(:row_number).to_a }
end

RSpec.configure { |c| c.include PipelineHelpers }

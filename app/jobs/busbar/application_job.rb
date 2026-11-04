module Busbar
  # Every BusBar job runs inside its run's tenant. The tenant id is serialized
  # with the job (from the current tenant at enqueue time), and perform runs
  # inside ActsAsTenant.with_tenant, so jobs work with require_tenant = true.
  # A job enqueued with no tenant raises.
  class ApplicationJob < ActiveJob::Base
    attr_accessor :tenant_id

    before_enqueue do |job|
      job.tenant_id ||= ActsAsTenant.current_tenant&.id
      raise MissingTenant, "#{job.class.name} enqueued without a tenant; wrap it in ActsAsTenant.with_tenant" unless job.tenant_id
    end

    around_perform do |job, block|
      raise MissingTenant, "#{job.class.name} has no tenant" unless job.tenant_id

      tenant = ActsAsTenant.without_tenant { Busbar.tenant_class.find(job.tenant_id) }
      ActsAsTenant.with_tenant(tenant) { block.call }
    end

    def serialize = super.merge("busbar_tenant_id" => tenant_id)

    def deserialize(job_data)
      super
      self.tenant_id = job_data["busbar_tenant_id"]
    end

    private

    # Jobs take run ids, not records, so nothing is looked up before the
    # tenant is set.
    def find_run(run_id) = Run.find(run_id)

    def fail_run!(run, error)
      run.update_columns(error: "#{error.class}: #{error.message}".truncate(2_000))
      run.transition_to!(:failed, error: error.message.truncate(500)) if run.can_transition_to?(:failed)
      ActiveSupport::Notifications.instrument("run.failed.busbar", run: run, error: error)
    end
  end
end

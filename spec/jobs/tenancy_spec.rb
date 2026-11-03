RSpec.describe "Job tenancy" do
  include ActiveJob::TestHelper

  it "refuses to enqueue a job with no tenant" do
    expect { Busbar::PrepareJob.perform_later(1) }.to raise_error(Busbar::MissingTenant)
  end

  it "serializes the current tenant and runs inside it" do
    tenant = create_tenant("Acme")
    ActsAsTenant.with_tenant(tenant) { Busbar::RetentionJob.perform_later }

    job = enqueued_jobs.last
    expect(job["busbar_tenant_id"]).to eq(tenant.id)

    seen = nil
    allow_any_instance_of(Busbar::RetentionJob).to receive(:perform) { seen = ActsAsTenant.current_tenant }
    perform_enqueued_jobs
    expect(seen).to eq(tenant)
  end
end

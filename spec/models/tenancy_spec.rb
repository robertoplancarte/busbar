# The dummy host's users are tenant-scoped the way BusBar expects host
# records to be: acts_as_tenant on the model, unique index led by account_id.
RSpec.describe User do
  let!(:acme) { Account.create!(name: "Acme") }
  let!(:globex) { Account.create!(name: "Globex") }

  before do
    ActsAsTenant.with_tenant(acme) { described_class.create!(external_id: "1001", email: "ana@acme.test") }
    ActsAsTenant.with_tenant(globex) { described_class.create!(external_id: "1001", email: "bo@globex.test") }
  end

  it "lets two tenants share a natural key" do
    expect(described_class.unscoped.where(external_id: "1001").count).to eq(2)
  end

  it "only sees the current tenant's records" do
    ActsAsTenant.with_tenant(acme) do
      expect(described_class.pluck(:email)).to eq([ "ana@acme.test" ])
    end
  end

  it "upserts on the tenant-led unique index" do
    described_class.upsert_all(
      [ { account_id: acme.id, external_id: "1001", email: "ana.new@acme.test" } ],
      unique_by: %i[account_id external_id], record_timestamps: true
    )

    ActsAsTenant.with_tenant(acme) { expect(described_class.sole.email).to eq("ana.new@acme.test") }
    ActsAsTenant.with_tenant(globex) { expect(described_class.sole.email).to eq("bo@globex.test") }
  end
end

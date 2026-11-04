RSpec.describe Busbar::Loaders::ActiveRecordSave do
  let(:acme) { create_tenant("Acme") }
  let(:schema) { Busbar.schema(:user) }
  let(:loader) { described_class.new(schema) }
  let(:context) { Busbar::Loader::Context.new(tenant: acme, natural_key: [ "email" ], load_mode: "incremental") }

  def row(data) = Busbar::Loader::Row.new(id: 1, key: [ data["email"] ], data: data)

  it "loads one record at a time, the shape a later Busbar.ingest_record (SSO, SCIM) will use" do
    outcome = loader.load_record(row("email" => "ana@acme.test", "name" => "Ana"), context)

    expect(outcome.status).to eq(:created)
    expect(outcome.record).to have_attributes(email: "ana@acme.test", tenant_id: acme.id, public_id: start_with("usr_"))
    expect(loader.load_record(row("email" => "ana@acme.test", "name" => "Ana"), context).status).to eq(:unchanged)
    expect(loader.load_record(row("email" => "ANA@acme.test", "name" => "Ana B"), context).status).to eq(:updated)
  end

  it "gives new users a random password nobody knows" do
    record = loader.load_record(row("email" => "ana@acme.test"), context).record

    expect(record.password_digest).to be_present
    expect(record.authenticate("")).to be(false)
  end

  it "lets the host choose the initial password" do
    custom = Class.new(described_class) { def initial_password(*) = "set-by-the-host-123" }

    record = custom.new(schema).load_record(row("email" => "ana@acme.test"), context).record

    expect(record.authenticate("set-by-the-host-123")).to be_truthy
  end

  it "returns model errors in the row error shape" do
    outcome = loader.load_record(row("email" => "ana@acme.test", "time_zone" => "Nowhere"), context)

    expect(outcome).to have_attributes(status: :failed, errors: [ { "field" => "time_zone", "message" => "isn't a time zone we know", "validator" => "model" } ])
  end

  it "reports a field the model does not have as a row error" do
    outcome = loader.load_record(row("email" => "ana@acme.test", "external_id" => "1001"), context)

    expect(outcome.status).to eq(:failed)
    expect(outcome.errors.first["message"]).to include("external_id")
  end

  it "skips existing records in create_only mode" do
    create_user(acme, email: "ana@acme.test")
    context.load_mode = "create_only"

    expect(loader.load_record(row("email" => "ana@acme.test", "name" => "New"), context).status).to eq(:skipped)
  end

  it "finds records by an encrypted key through the model" do
    user = create_user(acme, email: "ana@acme.test")

    found = ActsAsTenant.with_tenant(acme) { loader.find_existing([ [ "ana@acme.test" ], [ "nobody@acme.test" ] ], context) }

    expect(found).to eq(Busbar::Loader.key_string([ "ana@acme.test" ]) => user)
  end

  it "has no default deactivate, so the host decides what it means" do
    expect { loader.deactivate([ [ "ana@acme.test" ] ], context) }.to raise_error(NotImplementedError, /deactivate/)
  end
end

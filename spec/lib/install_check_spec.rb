RSpec.describe Busbar::InstallCheck do
  def messages(schema) = described_class.new.run([ schema ]).map { |f| [ f.level, f.message ] }

  it "is happy with the user schema on the per-row save loader, except for external_id, which locke lacks" do
    expect(messages(Busbar.schema(:user))).to eq([ [ :warning, "field external_id has no User#external_id; templates must not map it" ] ])
  end

  it "warns when the upsert loader targets a model with encrypts, has_secure_password or create callbacks" do
    schema = Busbar::Schema.build(:fast_user) do
      natural_key :email
      loader :active_record, model: "User"
      field :email, :email
    end

    warnings = messages(schema).select { |level, _| level == :warning }.map(&:last)
    expect(warnings).to contain_exactly(
      a_string_including("encrypts (email, otp_secret, name)"),
      a_string_including("has_secure_password"),
      a_string_including("create callbacks")
    )
    expect(warnings).to all(include("loader :active_record_save"))
  end

  it "does not warn about a plain model" do
    schema = Busbar::Schema.build(:employee) do
      natural_key :external_id
      loader :active_record, model: "Employee"
      field :external_id, :string
    end

    expect(messages(schema)).to be_empty
  end

  it "requires a unique index led by the tenant column for upsert_all" do
    schema = Busbar::Schema.build(:employee_by_email) do
      natural_key :email
      loader :active_record, model: "Employee"
      field :email, :email
    end

    expect(messages(schema)).to eq([ [ :error, "employees needs a unique index on (tenant_id, email) for upsert_all" ] ])
  end
end

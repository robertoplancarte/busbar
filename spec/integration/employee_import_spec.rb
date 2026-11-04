# The fast path: a plain model loaded with upsert_all on (tenant_id, external_id).
RSpec.describe "Importing employees with the upsert loader", type: :model do
  let(:acme) { create_tenant("Acme") }
  let(:globex) { create_tenant("Globex") }
  let(:map) { { "Emp #" => "external_id", "Work Email" => "email", "Name" => "name", "Start" => "hired_on", "Status" => "status" } }

  before do
    Busbar.define_schema(:employee) do
      natural_key :external_id
      loader :active_record, model: "Employee"
      field :external_id, :string, required: true, synonyms: [ "emp #" ]
      field :email, :email, required: true
      field :name, :string
      field :hired_on, :date
      field :status, :enum, values: Employee::STATUSES
    end
  end

  after { Busbar.schemas.instance_variable_get(:@entries).delete("employee") }

  def import_employees(tenant)
    template = ActsAsTenant.with_tenant(tenant) do
      Busbar::Template.create!(name: "HR export", schema_key: "employee", column_map: map,
                               transforms: [ { "field" => "hired_on", "step" => "parse_date", "args" => { "format" => "%m/%d/%Y" } } ])
    end
    import(tenant, "employees.csv", schema: :employee, template: template, column_map: map)
  end

  it "writes the tenant column itself and upserts on the tenant-led index" do
    ActsAsTenant.with_tenant(globex) { Employee.create!(external_id: "1001", email: "x@globex.test") }

    run = import_employees(acme)

    expect(run.state).to eq("completed")
    ActsAsTenant.with_tenant(acme) do
      expect(Employee.order(:external_id).pluck(:external_id, :tenant_id, :hired_on, :status)).to eq(
        [ [ "1001", acme.id, Date.new(2024, 3, 1), "active" ], [ "1002", acme.id, Date.new(2024, 4, 15), "leave" ] ]
      )
    end
    ActsAsTenant.with_tenant(globex) { expect(Employee.sole.email).to eq("x@globex.test") }
  end

  it "updates on a second run and leaves unchanged rows alone" do
    import_employees(acme)
    ActsAsTenant.with_tenant(acme) { Employee.find_by(external_id: "1002").update!(name: "Renamed") }

    run = import_employees(acme)

    expect(rows_of(run).map(&:action)).to eq(%w[unchanged update])
    ActsAsTenant.with_tenant(acme) { expect(Employee.find_by(external_id: "1002").name).to eq("Bo Diaz") }
  end

  it "uses a saved template with no mapping stop" do
    run = import_employees(acme)

    expect(run.transitions.order(:sort_key).pluck(:to_state)).to eq(%w[preparing staging validating ready loading completed])
  end
end

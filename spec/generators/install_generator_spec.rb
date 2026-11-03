require "generators/busbar/install/install_generator"

RSpec.describe Busbar::Generators::InstallGenerator do
  let(:root) { Rails.root.join("tmp", "generator_test") }

  before do
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p(root.join("config"))
    File.write(root.join("config", "routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  after { FileUtils.rm_rf(root) }

  def generate(*args) = capture_output { described_class.start(args, destination_root: root) }

  def capture_output
    out = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = out
  end

  it "writes a migration keyed to the Tenant table, the initializer and the route" do
    generate("--tenant-class=Tenant")

    migration = Dir[root.join("db", "migrate", "*_create_busbar_tables.rb")].sole
    expect(File.read(migration)).to include("foreign_key: { to_table: :tenants }").and include("ActiveRecord::Migration[8.1]")
    initializer = File.read(root.join("config", "initializers", "busbar.rb"))
    expect(initializer).to include('c.tenant_class  = "Tenant"', "c.tenant_column = :tenant_id",
                                   "c.authorize = ->(_user, _action, _record) { false }")
    expect(File.read(root.join("config", "routes.rb"))).to include('mount Busbar::Engine, at: "/busbar"')
  end

  it "takes another tenant model and column" do
    generate("--tenant-class=Organization", "--tenant-column=org_id")

    expect(File.read(Dir[root.join("db", "migrate", "*.rb")].sole)).to include("to_table: :organizations")
    expect(File.read(root.join("config", "initializers", "busbar.rb"))).to include("c.tenant_column = :org_id")
  end

  it "produces the migration the dummy app runs" do
    generate("--tenant-class=Tenant")

    generated = File.read(Dir[root.join("db", "migrate", "*.rb")].sole)
    expect(generated).to eq(File.read(Rails.root.join("db", "migrate", "20261101000005_create_busbar_tables.rb")))
  end
end

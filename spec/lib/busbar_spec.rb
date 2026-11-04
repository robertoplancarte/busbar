RSpec.describe Busbar do
  around do |example|
    saved = described_class.config
    example.run
  ensure
    described_class.instance_variable_set(:@config, saved)
  end

  it "has a version" do
    expect(Busbar::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe ".configure" do
    it "assumes no tenant model until the host names one" do
      described_class.reset_config!

      expect(described_class.config.tenant_class).to be_nil
      expect { described_class.tenant_class }.to raise_error(Busbar::ConfigurationError)
    end

    it "derives the tenant column from the tenant class, as acts_as_tenant does" do
      described_class.reset_config!
      described_class.configure { |c| c.tenant_class = "Tenant" }

      expect(described_class.tenant_column).to eq(:tenant_id)
    end

    it "lets the host name a different tenant column" do
      described_class.reset_config!
      described_class.configure do |c|
        c.tenant_class = "Organization"
        c.tenant_column = :org_id
      end

      expect(described_class.tenant_column).to eq(:org_id)
    end

    it "starts from the defaults in the spec" do
      described_class.reset_config!
      config = described_class.config

      expect(config.chunk_size).to eq(5_000)
      expect(config.retention).to eq(30.days)
    end

    it "uses the dummy app's Tenant, like locke" do
      expect(described_class.tenant_class).to eq(Tenant)
      expect(described_class.tenant_column).to eq(:tenant_id)
    end
  end

  describe ".authorized?" do
    it "denies when the host has not configured authorize" do
      described_class.reset_config!

      expect(described_class.authorized?(Object.new, :approve, nil)).to be(false)
    end

    it "uses the host's callable" do
      described_class.configure { |c| c.authorize = ->(user, action, _record) { user == :admin && action == :approve } }

      expect(described_class.authorized?(:admin, :approve, nil)).to be(true)
      expect(described_class.authorized?(:member, :approve, nil)).to be(false)
    end
  end

  describe "the :busbar load hook" do
    it "runs registered hooks with the Busbar module" do
      received = nil
      ActiveSupport.on_load(:busbar) { received = self }

      expect(received).to eq(Busbar)
    end
  end
end

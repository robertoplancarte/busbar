RSpec.describe Busbar do
  after { described_class.reset_config! }

  it "has a version" do
    expect(Busbar::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe ".configure" do
    it "starts from the defaults in the spec" do
      described_class.reset_config!
      config = described_class.config

      expect(config.tenant_class).to eq("Account")
      expect(config.tenant_column).to eq(:account_id)
      expect(config.chunk_size).to eq(5_000)
      expect(config.retention).to eq(30.days)
    end

    it "yields the configuration to the host" do
      described_class.configure { |c| c.chunk_size = 1_000 }

      expect(described_class.config.chunk_size).to eq(1_000)
    end

    it "resolves the tenant class" do
      expect(described_class.tenant_class).to eq(Account)
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

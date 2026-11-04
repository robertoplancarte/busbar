RSpec.describe Busbar::Schema do
  let(:user) { Busbar.schema(:user) }

  def process(input, **opts) = user.process(input, **opts)

  describe "the shipped user schema" do
    it "matches by external_id when the file has one, otherwise by email" do
      expect(user.natural_key_for(%w[external_id email name])).to eq(%w[external_id])
      expect(user.natural_key_for(%w[email name])).to eq(%w[email])
      expect(user.natural_key_for(%w[external_id email], %w[email])).to eq(%w[email])
    end

    it "lowercases and strips the email key" do
      expect(process({ "email" => "  Ana@ACME.test " }).data["email"]).to eq("ana@acme.test")
    end

    it "builds name from first_name and last_name, unless the file has a name" do
      expect(process({ "email" => "a@b.test", "first_name" => "Ana", "last_name" => "Lima" }).data["name"]).to eq("Ana Lima")
      expect(process({ "email" => "a@b.test", "name" => "Ana L.", "first_name" => "Ana" }).data["name"]).to eq("Ana L.")
    end

    it "accepts Rails and IANA time zone names and stores the IANA one" do
      expect(process({ "email" => "a@b.test", "time_zone" => "Pacific Time (US & Canada)" }).data["time_zone"]).to eq("America/Los_Angeles")
      expect(process({ "email" => "a@b.test", "time_zone" => "europe/madrid" }).data["time_zone"]).to eq("Europe/Madrid")
      expect(process({ "email" => "a@b.test", "time_zone" => "Mars" }).errors).to eq(
        [ { "field" => "time_zone", "message" => "isn't a time zone we know", "validator" => "time_zone" } ]
      )
    end

    it "limits name to 100 characters, like locke" do
      expect(process({ "email" => "a@b.test", "name" => "x" * 101 }).errors.first["message"]).to eq("is too long (maximum 100)")
    end

    it "never writes first_name or last_name to the model" do
      expect(user.loadable_fields).to eq(%w[external_id email name time_zone])
    end
  end

  describe "from JSON" do
    it "builds the same schema as the Ruby DSL" do
      schema = described_class.from_h(
        "key" => "employee", "natural_key" => [ "external_id" ], "loader" => "active_record:Employee",
        "fields" => [ { "name" => "external_id", "type" => "string", "required" => true },
                      { "name" => "status", "type" => "enum", "values" => %w[active leave] } ],
        "rules" => []
      )

      expect(schema.model_name).to eq("Employee")
      expect(schema.process({ "external_id" => "1", "status" => "LEAVE" }).data).to eq("external_id" => "1", "status" => "leave")
      expect(schema.process({ "status" => "gone" }).errors.map { |e| e["field"] }).to eq(%w[external_id status])
    end
  end

  describe "template transforms and value maps" do
    it "applies them before casting" do
      result = process({ "email" => "a@b.test", "time_zone" => "CDMX" },
                       template_transforms: [ { "field" => "time_zone", "step" => "value_map" } ],
                       value_maps: { "time_zone" => { "cdmx" => "America/Mexico_City" } })

      expect(result.data["time_zone"]).to eq("America/Mexico_City")
    end
  end

  describe "types" do
    let(:field) { Busbar::Schema::Field.new(name: "x", options: {}) }

    it "casts money, booleans and dates" do
      expect(Busbar::Types::Money.cast("($1,234.50)", field)).to eq(BigDecimal("-1234.5"))
      expect(Busbar::Types::Boolean.cast("Yes", field)).to be(true)
      expect(Busbar::Types::Date.cast("2024-03-01", field)).to eq(Date.new(2024, 3, 1))
      expect { Busbar::Types::Integer.cast("1.5", field) }.to raise_error(Busbar::Types::Invalid)
    end
  end
end

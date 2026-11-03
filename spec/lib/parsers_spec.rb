RSpec.describe Busbar::Parsers do
  def rows(name, options = {})
    path = Rails.root.join("..", "fixtures", "files", name).to_s
    parser = described_class.for(path, options: options)
    [ parser, parser.each_row.map { |row, _number| row } ]
  end

  it "reads UTF-8 CSV with a byte order mark" do
    parser, data = rows("users.csv")

    expect(parser.headers).to eq([ "Email", "Full Name", "Time Zone" ])
    expect(data.first).to eq("Email" => "ana@acme.test", "Full Name" => "Ana Lima", "Time Zone" => "America/Mexico_City")
  end

  it "detects semicolons" do
    parser, data = rows("users_split_names.csv")

    expect(parser.detected).to eq("encoding" => "UTF-8", "delimiter" => ";")
    expect(data.first["Last"]).to eq("Lima")
  end

  it "transcodes Windows-1252 TSV to UTF-8" do
    parser, data = rows("users_windows1252.tsv")

    expect(parser.detected).to eq("encoding" => "Windows-1252", "delimiter" => "\t")
    expect(data.first).to eq("Email" => "joé@acme.test", "Full Name" => "José Álvarez")
  end

  it "reads XLSX, keeping whole numbers whole" do
    parser, data = rows("users.xlsx")

    expect(parser).to be_a(Busbar::Parsers::Xlsx)
    expect(data.last).to eq("Email" => "bo@acme.test", "Full Name" => "Bo Diaz", "Employee Number" => "1002")
  end

  it "reads a JSON object holding an array, flattening nested objects to dot paths" do
    parser, data = rows("users.json")

    expect(parser).to be_a(Busbar::Parsers::Json)
    expect(data.first).to eq("email" => "ana@acme.test", "profile.name" => "Ana Lima", "profile.tz" => "UTC")
  end

  it "streams NDJSON" do
    parser, data = rows("users.ndjson")

    expect(parser).to be_a(Busbar::Parsers::Ndjson)
    expect(data.map { |r| r["email"] }).to eq(%w[ana@acme.test bo@acme.test])
  end

  it "rejects binary files" do
    path = Rails.root.join("tmp", "binary.bin").to_s
    File.binwrite(path, "\x00\x01\x02garbage")

    expect { described_class.for(path) }.to raise_error(Busbar::Parsers::UnsupportedFormat)
  end
end

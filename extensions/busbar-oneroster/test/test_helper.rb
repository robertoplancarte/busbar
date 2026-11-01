# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "busbar/oneroster"
require "minitest/autorun"
require "tmpdir"

module PackageHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  # Builds a zip from a fixture folder. `replace` swaps file contents,
  # `drop` removes files, `extra` adds raw entries (name => content).
  def build_zip(fixture = "bulk", replace: {}, drop: [], extra: {})
    files = Dir[File.join(FIXTURES, fixture, "*.csv")].to_h { |p| [File.basename(p), File.read(p)] }
    files.merge!(replace)
    drop.each { |name| files.delete(name) }
    files.merge!(extra)

    path = File.join(Dir.mktmpdir("oneroster-test"), "roster.zip")
    Zip::OutputStream.open(path) do |zos|
      files.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end
    path
  end

  def fixture(name, fixture = "bulk") = File.read(File.join(FIXTURES, fixture, name))
end

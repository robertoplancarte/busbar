# frozen_string_literal: true

require "test_helper"
require "busbar/oneroster/extension"

# Records the calls the gem makes against the engine's extension API as
# specified (Busbar.register_extension and friends). It checks the gem's side
# of the contract; the engine's own suite must check the other side.
class ExtensionContractTest < Minitest::Test
  include PackageHelpers

  class Recorder
    attr_reader :calls

    def initialize = @calls = Hash.new { |h, k| h[k] = [] }
    def register_extension(name, version:)
      @calls[:extension] << [name, version]
      yield self
    end
    def transform(name, klass) = @calls[:transform] << [name, klass]
    def package_handler(klass) = @calls[:package_handler] << klass
    def template(key, **opts) = @calls[:template] << [key, opts]

    def schema(key)
      builder = SchemaRecorder.new
      yield builder
      @calls[:schema] << [key, builder]
    end
  end

  class SchemaRecorder
    attr_reader :fields, :natural_key_value, :scope_key_value

    def initialize = @fields = {}
    def natural_key(key) = @natural_key_value = key
    def scope_key(key) = @scope_key_value = key
    def field(name, type, **opts) = @fields[name] = [type, opts]
  end

  def setup
    @recorder = Recorder.new
    Busbar::OneRoster::Extension.register!(@recorder)
  end

  def test_registers_every_rostering_file
    keys = @recorder.calls[:schema].map(&:first)
    assert_equal Busbar::OneRoster::FILE_SPECS.map { |s| :"oneroster_#{s.schema}" }, keys
    assert_equal keys, @recorder.calls[:template].map(&:first)
    assert_equal [[:oneroster, Busbar::OneRoster::VERSION]], @recorder.calls[:extension]
  end

  def test_users_schema_shape
    _, users = @recorder.calls[:schema].find { |k, _| k == :oneroster_users }
    assert_equal :sourced_id, users.natural_key_value
    assert_equal :source_system, users.scope_key_value
    assert_equal [:boolean, { required: true }], users.fields["enabled_user"]
    assert_equal [:array, { references: :oneroster_users }], users.fields["agent_sourced_ids"]
    assert_equal [:string, { references: :oneroster_orgs }], users.fields["primary_org_sourced_id"]
  end

  def test_package_handler_plan
    handler = Busbar::OneRoster::PackageHandler.new(build_zip)
    plan = handler.open
    assert_equal "example-sis", plan[:metadata][:source_system]
    users = plan[:children].find { |c| c[:schema] == :oneroster_users }
    assert_equal :snapshot_deactivate, users[:load_mode]
    assert_equal({ mode: "bulk" }, users[:metadata])
    handler.close
  end

  def test_package_handler_returns_errors_instead_of_raising
    plan = Busbar::OneRoster::PackageHandler.new(build_zip(drop: ["roles.csv"])).open
    assert_equal ["manifest declares roles.csv as bulk but the file is missing"], plan[:errors]
  end

  # Minimal stand-ins for the engine's staged row and context.
  StagedRow = Struct.new(:raw, :data, :errors, :action) do
    def add_error(field, message) = errors[field] = message
  end
  Meta = Struct.new(:metadata)
  Context = Struct.new(:package, :package_entry)

  def test_row_transform_fills_staged_row
    raw = CSV.parse(fixture("users.csv"), headers: true).first.to_h
    row = StagedRow.new(raw, {}, {}, nil)
    context = Context.new(Meta.new({ source_system: "example-sis" }), Meta.new({ mode: "bulk" }))
    Busbar::OneRoster::RowTransform.new(file: "users.csv").call(row, context)
    assert_empty row.errors
    assert_equal :upsert, row.action
    assert_equal "example-sis", row.data["source_system"]
    assert_equal "Edna", row.data["given_name"]
  end
end

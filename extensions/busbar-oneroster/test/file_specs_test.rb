# frozen_string_literal: true

require "test_helper"

class FileSpecsTest < Minitest::Test
  include Busbar::OneRoster

  def test_references_only_point_backwards_or_to_self
    seen = []
    FILE_SPECS.each do |spec|
      spec.references.each_value do |target|
        assert(target == spec.schema || seen.include?(target),
               "#{spec.file} references #{target}, which is loaded later")
      end
      seen << spec.schema
    end
  end

  def test_every_file_starts_with_common_columns
    FILE_SPECS.each { |spec| assert_equal COMMON, spec.columns.first(3), spec.file }
  end

  def test_typed_columns_exist_in_header
    FILE_SPECS.each do |spec|
      typed = spec.required + spec.references.keys + spec.multi_value + spec.enums.keys +
              spec.dates + spec.booleans + spec.years
      assert_empty typed - spec.columns, "#{spec.file} types columns it does not have"
    end
  end

  def test_field_name
    assert_equal "sourced_id", Busbar::OneRoster.field_name("sourcedId")
    assert_equal "primary_org_sourced_id", Busbar::OneRoster.field_name("primaryOrgSourcedId")
    assert_equal "sms", Busbar::OneRoster.field_name("sms")
  end
end

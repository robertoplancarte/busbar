# frozen_string_literal: true

require "test_helper"
require "csv"

class RowConverterTest < Minitest::Test
  include PackageHelpers
  R = Busbar::OneRoster::RowConverter

  def users_spec = Busbar::OneRoster.file_spec("users.csv")
  def enrollments_spec = Busbar::OneRoster.file_spec("enrollments.csv")

  def rows(file) = CSV.parse(fixture(file), headers: true).map(&:to_h)

  def test_bulk_user_row_is_typed
    result = R.new(users_spec, mode: "bulk").call(rows("users.csv").first)
    assert result.valid?, result.errors.inspect
    assert_equal :upsert, result.action
    assert_equal "u1", result.data["sourced_id"]
    assert_equal true, result.data["enabled_user"]
    assert_equal ["{LDAP:ek1}", "{Fed:ek-9}"], result.data["user_ids"]
    assert_equal "s1", result.data["primary_org_sourced_id"]
    assert_nil result.data["middle_name"]
  end

  def test_bulk_rejects_status_values
    row = rows("users.csv").first.merge("status" => "active")
    result = R.new(users_spec, mode: "bulk").call(row)
    assert_equal "must be empty in a bulk file", result.errors["status"]
  end

  def test_delta_tobedeleted_deactivates
    row = rows("enrollments.csv").first.merge("status" => "tobedeleted",
                                               "dateLastModified" => "2026-01-05T10:00:00.000Z")
    result = R.new(enrollments_spec, mode: "delta").call(row)
    assert result.valid?, result.errors.inspect
    assert_equal :deactivate, result.action
  end

  def test_delta_requires_status_and_timestamp
    result = R.new(enrollments_spec, mode: "delta").call(rows("enrollments.csv").first)
    assert_equal "is required in a delta file", result.errors["status"]
    assert_equal "is required in a delta file", result.errors["date_last_modified"]
  end

  def test_collects_every_error_in_a_row
    row = rows("enrollments.csv").first.merge("role" => "coach", "primary" => "yes",
                                               "userSourcedId" => "", "beginDate" => "8/15/2025")
    errors = R.new(enrollments_spec, mode: "bulk").call(row).errors
    assert_equal %w[begin_date primary role user_sourced_id], errors.keys.sort
    assert_equal "is required", errors["user_sourced_id"]
  end

  def test_rejects_unknown_mode
    assert_raises(ArgumentError) { R.new(users_spec, mode: "full") }
  end
end

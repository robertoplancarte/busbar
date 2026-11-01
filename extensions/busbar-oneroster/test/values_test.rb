# frozen_string_literal: true

require "test_helper"

class ValuesTest < Minitest::Test
  V = Busbar::OneRoster::Values
  E = Busbar::OneRoster::ValueError

  def test_multi_value
    assert_equal %w[1 2], V.multi_value("1, 2")
    assert_equal [], V.multi_value("")
    assert_equal ["{LDAP:ek1}", "{Fed:ek-9}"], V.multi_value("{LDAP:ek1},{Fed:ek-9}")
  end

  def test_date
    assert_equal Date.new(2025, 8, 15), V.date("2025-08-15")
    assert_nil V.date(" ")
    assert_raises(E) { V.date("08/15/2025") }
    assert_raises(E) { V.date("2025-02-30") }
  end

  def test_datetime_must_be_utc
    assert_equal Time.utc(2012, 4, 23, 18, 25, 43.511r), V.datetime("2012-04-23T18:25:43.511Z")
    assert_raises(E) { V.datetime("2012-04-23T18:25:43+02:00") }
    assert_raises(E) { V.datetime("2012-04-23") }
  end

  def test_boolean_is_lowercase_true_false_only
    assert_equal true, V.boolean("true")
    assert_equal false, V.boolean("false")
    assert_raises(E) { V.boolean("TRUE") }
    assert_raises(E) { V.boolean("1") }
  end

  def test_enum_accepts_ext_terms
    assert_equal "teacher", V.enum("teacher", %w[teacher student])
    assert_equal "ext:coach", V.enum("ext:coach", %w[teacher student])
    assert_raises(E) { V.enum("coach", %w[teacher student]) }
  end

  def test_year
    assert_equal 2026, V.year("2026")
    assert_raises(E) { V.year("25-26") }
  end
end

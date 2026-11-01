# frozen_string_literal: true

require "test_helper"

class ManifestTest < Minitest::Test
  include PackageHelpers
  M = Busbar::OneRoster::Manifest

  def test_parses_modes_and_source
    m = M.parse(fixture("manifest.csv"))
    assert_empty m.problems
    assert_equal "bulk", m.mode_for("users.csv")
    assert_equal "absent", m.mode_for("demographics.csv")
    assert_equal "example-sis", m.source_system_code
  end

  def test_handles_bom
    m = M.parse("﻿" + fixture("manifest.csv"))
    assert_equal "1.2", m.oneroster_version
  end

  def test_reports_wrong_version_and_unknown_mode
    text = fixture("manifest.csv").sub("oneroster.version,1.2", "oneroster.version,1.1")
                                  .sub("file.users,bulk", "file.users,full")
    problems = M.parse(text).problems
    assert(problems.any? { |p| p.include?("oneroster.version must be 1.2") })
    assert(problems.any? { |p| p.include?("users.csv: unknown mode") })
  end

  def test_rejects_wrong_header
    assert_raises(Busbar::OneRoster::PackageError) { M.parse("name,value\nx,y\n") }
  end
end

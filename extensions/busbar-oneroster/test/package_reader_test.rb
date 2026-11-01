# frozen_string_literal: true

require "test_helper"

class PackageReaderTest < Minitest::Test
  include PackageHelpers
  PR = Busbar::OneRoster::PackageReader
  PE = Busbar::OneRoster::PackageError

  def read(path, **opts) = PR.new(path, **opts).read

  def test_reads_bulk_package_in_dependency_order
    package = read(build_zip)
    assert_equal %i[orgs academic_sessions courses classes users roles enrollments], package.entries.map(&:schema)
    assert(package.entries.all? { |e| e.mode == "bulk" })
    assert_equal 3, package.entries.find { |e| e.schema == :users }.row_count
    assert_equal "example-sis", package.source_system
    assert_empty package.warnings
    paths = package.entries.map(&:path)
    package.close
    refute(paths.any? { |p| File.exist?(p) }, "temp files should be removed on close")
  end

  def test_package_detection
    assert PR.package?(build_zip)
    assert PR.package?(build_zip(drop: ["users.csv"], replace: { "manifest.csv" => fixture("manifest.csv").sub("file.users,bulk", "file.users,absent") }))
    refute PR.package?(build_zip(drop: ["manifest.csv"]))
    not_zip = File.join(Dir.mktmpdir, "users.csv")
    File.write(not_zip, fixture("users.csv"))
    refute PR.package?(not_zip)
  end

  def test_missing_declared_file
    error = assert_raises(PE) { read(build_zip(drop: ["roles.csv"])) }
    assert_includes error.problems, "manifest declares roles.csv as bulk but the file is missing"
  end

  def test_file_present_but_absent_in_manifest_is_inferred
    manifest = fixture("manifest.csv") # declares demographics as absent
    demographics = "sourcedId,status,dateLastModified,birthDate,sex,americanIndianOrAlaskaNative,asian," \
                   "blackOrAfricanAmerican,nativeHawaiianOrOtherPacificIslander,white,demographicRaceTwoOrMoreRaces," \
                   "hispanicOrLatinoEthnicity,countryOfBirthCode,stateOfBirthAbbreviation,cityOfBirth," \
                   "publicSchoolResidenceStatus\n" \
                   "u2,active,2026-01-05T10:00:00.000Z,2016-04-01,male,false,false,false,false,true,false,false,US,IL,Springfield,\n"
    package = read(build_zip(replace: { "manifest.csv" => manifest }, extra: { "demographics.csv" => demographics }))
    entry = package.entries.find { |e| e.schema == :demographics }
    assert_equal "delta", entry.mode
    assert(package.warnings.any? { |w| w.start_with?("demographics.csv is present") })
  end

  def test_header_mismatch_reports_details
    bad = fixture("users.csv").sub("pronouns", "pronoun")
    error = assert_raises(PE) { read(build_zip(replace: { "users.csv" => bad })) }
    assert(error.problems.any? { |p| p.include?("users.csv: header does not match") && p.include?("missing pronouns") && p.include?("unexpected pronoun") })
  end

  def test_reordered_header_is_rejected
    lines = fixture("orgs.csv").lines
    lines[0] = "sourcedId,status,dateLastModified,type,name,identifier,parentSourcedId\n"
    error = assert_raises(PE) { read(build_zip(replace: { "orgs.csv" => lines.join })) }
    assert(error.problems.any? { |p| p.include?("columns are out of order") })
  end

  def test_rejects_files_in_folders
    error = assert_raises(PE) { read(build_zip(extra: { "nested/users.csv" => fixture("users.csv") })) }
    assert(error.problems.any? { |p| p.include?("must sit at the root") })
  end

  def test_rejects_zip_bombs
    bomb = "a" * 5_000_000
    error = assert_raises(PE) { read(build_zip(extra: { "notes.csv" => bomb })) }
    assert(error.problems.any? { |p| p.include?("compression ratio") })
  end

  def test_enforces_size_limit
    error = assert_raises(PE) { read(build_zip, limits: { max_uncompressed_bytes: 100 }) }
    assert(error.problems.any? { |p| p.include?("the limit is 100") })
  end

  def test_unsupported_and_unknown_files_are_warnings
    package = read(build_zip(extra: { "lineItems.csv" => "sourcedId\n", "notes.csv" => "x\n" }))
    assert_includes package.warnings, "lineItems.csv is not imported by busbar-oneroster #{Busbar::OneRoster::VERSION}; skipped"
    assert_includes package.warnings, "notes.csv is not a OneRoster 1.2 file; skipped"
  end

  def test_not_a_zip
    path = File.join(Dir.mktmpdir, "roster.zip")
    File.write(path, "not a zip")
    error = assert_raises(PE) { read(path) }
    assert(error.problems.first.start_with?("not a readable zip file"))
  end
end

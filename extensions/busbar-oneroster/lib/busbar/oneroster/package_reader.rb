# frozen_string_literal: true

require "csv"
require "tempfile"
require "zip"

module Busbar
  module OneRoster
    # Opens a OneRoster 1.2 CSV zip package safely and returns its importable
    # files in dependency order.
    #
    #   package = PackageReader.new("/tmp/roster.zip").read
    #   package.entries.each { |e| e.spec.schema; e.mode; e.path }
    #   package.close  # removes the extracted temp files
    class PackageReader
      Entry = Struct.new(:spec, :mode, :path, :row_count, keyword_init: true) do
        def file = spec.file
        def schema = spec.schema
      end

      Package = Struct.new(:manifest, :entries, :warnings, :tempfiles, keyword_init: true) do
        def close = tempfiles.each(&:close!)
        def bulk? = entries.any? { |e| e.mode == "bulk" }
        def source_system = manifest.source_system_code || manifest.source_system_name
      end

      DEFAULT_LIMITS = {
        max_entries: 64,
        max_uncompressed_bytes: 2 * 1024**3, # 2 GB across all files
        max_ratio: 200                        # zip-bomb guard: uncompressed / compressed
      }.freeze

      def self.package?(path)
        Zip::File.open(path) { |zip| !zip.find_entry(MANIFEST_FILE).nil? }
      rescue Zip::Error
        false
      end

      def initialize(path, limits: {})
        @path = path
        @limits = DEFAULT_LIMITS.merge(limits)
      end

      def read
        problems = []
        warnings = []
        tempfiles = []

        Zip::File.open(@path) do |zip|
          entries = zip.entries.reject(&:directory?)
          problems.concat(structure_problems(entries))
          raise PackageError, problems if problems.any?

          manifest_entry = zip.find_entry(MANIFEST_FILE)
          raise PackageError, ["package has no manifest.csv at its root"] unless manifest_entry

          manifest = Manifest.parse(manifest_entry.get_input_stream.read)
          problems.concat(manifest.problems)

          names = entries.map(&:name)
          result_entries = []

          FILE_SPECS.each do |spec|
            declared = manifest.mode_for(spec.file)
            present = names.include?(spec.file)

            if present && (declared.nil? || declared == "absent")
              # The binding says data files win over the manifest; infer the mode.
              warnings << "#{spec.file} is present but the manifest says #{declared || 'nothing'}; " \
                          "treating it as #{inferred_mode(zip, spec)}"
              declared = inferred_mode(zip, spec)
            elsif !present && %w[bulk delta].include?(declared)
              problems << "manifest declares #{spec.file} as #{declared} but the file is missing"
              next
            end
            next unless present

            tempfile = extract(zip.find_entry(spec.file), tempfiles)
            header_problem = header_problem(tempfile.path, spec)
            if header_problem
              problems << header_problem
              next
            end

            result_entries << Entry.new(spec: spec, mode: declared, path: tempfile.path,
                                        row_count: count_rows(tempfile.path))
          end

          (names - FILE_SPECS.map(&:file) - [MANIFEST_FILE]).each do |name|
            warnings << if UNSUPPORTED_FILES.include?(name)
                          "#{name} is not imported by busbar-oneroster #{VERSION}; skipped"
                        else
                          "#{name} is not a OneRoster 1.2 file; skipped"
                        end
          end

          problems << "package contains no importable OneRoster files" if result_entries.empty? && problems.empty?

          if problems.any?
            tempfiles.each(&:close!)
            raise PackageError, problems
          end

          Package.new(manifest: manifest, entries: result_entries, warnings: warnings, tempfiles: tempfiles)
        end
      rescue Zip::Error => e
        tempfiles&.each(&:close!)
        raise PackageError, ["not a readable zip file (#{e.message})"]
      end

      private

      def structure_problems(entries)
        list = []
        list << "package has #{entries.size} files; the limit is #{@limits[:max_entries]}" if entries.size > @limits[:max_entries]

        entries.each do |e|
          list << "#{e.name}: files must sit at the root of the zip, not in a folder" if e.name.include?("/") || e.name.include?("\\")
          if e.compressed_size.positive? && e.size / e.compressed_size.to_f > @limits[:max_ratio]
            list << "#{e.name}: compression ratio is too high to be a real CSV"
          end
        end

        dupes = entries.map(&:name).tally.select { |_, n| n > 1 }.keys
        list.concat(dupes.map { |n| "#{n} appears more than once" })

        total = entries.sum(&:size)
        if total > @limits[:max_uncompressed_bytes]
          list << "package expands to #{total} bytes; the limit is #{@limits[:max_uncompressed_bytes]}"
        end
        list
      end

      # Stream the entry to a temp file without trusting its name for the path.
      def extract(entry, tempfiles)
        tempfile = Tempfile.new(["oneroster-", ".csv"], binmode: true)
        tempfiles << tempfile
        written = 0
        entry.get_input_stream do |input|
          while (chunk = input.read(64 * 1024))
            written += chunk.bytesize
            raise PackageError, ["#{entry.name} is larger than its zip header claims"] if written > entry.size

            tempfile.write(chunk)
          end
        end
        tempfile.flush
        tempfile.rewind
        tempfile
      end

      def first_line(path)
        File.open(path, "rb") { |f| f.gets.to_s }.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
      end

      # OneRoster files must carry the exact header, in order.
      def header_problem(path, spec)
        header = CSV.parse_line(first_line(path)) || []
        header = header.map { |h| h.to_s.strip }
        return nil if header == spec.columns

        missing = spec.columns - header
        extra = header - spec.columns
        details = []
        details << "missing #{missing.join(', ')}" if missing.any?
        details << "unexpected #{extra.join(', ')}" if extra.any?
        details << "columns are out of order" if details.empty?
        "#{spec.file}: header does not match OneRoster #{SPEC_VERSION} (#{details.join('; ')})"
      rescue CSV::MalformedCSVError => e
        "#{spec.file}: header row is not valid CSV (#{e.message})"
      end

      # A file whose rows carry status values is a delta file.
      def inferred_mode(zip, spec)
        @inferred ||= {}
        @inferred[spec.file] ||= begin
          sample = zip.find_entry(spec.file).get_input_stream.read(256 * 1024).to_s
          sample = sample.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
          lines = sample.lines
          lines.pop if lines.size > 1 && !sample.end_with?("\n") # drop a partial last line
          rows = CSV.parse(lines.join, headers: true)
          rows.any? { |r| !r["status"].to_s.strip.empty? } ? "delta" : "bulk"
        rescue CSV::MalformedCSVError
          "bulk"
        end
      end

      def count_rows(path)
        count = 0
        CSV.foreach(path, headers: true, encoding: "bom|utf-8") { count += 1 }
        count
      end
    end
  end
end

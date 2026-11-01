# frozen_string_literal: true

require "csv"

module Busbar
  module OneRoster
    # Parses manifest.csv: two columns, propertyName and value.
    #
    #   manifest.version,1.0
    #   oneroster.version,1.2
    #   file.users,bulk          # bulk | delta | absent
    #   source.systemName,Acme SIS
    class Manifest
      MODES = %w[bulk delta absent].freeze

      attr_reader :properties

      def self.parse(io_or_string)
        new(io_or_string)
      end

      def initialize(io_or_string)
        text = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string.to_s
        text = text.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
        rows = CSV.parse(text, headers: true)
        unless rows.headers.compact.map(&:strip) == %w[propertyName value]
          raise PackageError, ["manifest.csv header must be propertyName,value (got #{rows.headers.join(',')})"]
        end

        @properties = {}
        rows.each do |row|
          name = row["propertyName"].to_s.strip
          next if name.empty?

          @properties[name] = row["value"].to_s.strip
        end
      end

      def manifest_version = properties["manifest.version"]
      def oneroster_version = properties["oneroster.version"]
      def source_system_name = properties["source.systemName"]
      def source_system_code = properties["source.systemCode"]

      # "users.csv" -> "bulk" | "delta" | "absent" | nil (not declared)
      def mode_for(file)
        properties["file.#{File.basename(file, '.csv')}"]&.downcase
      end

      def declared_files
        properties.filter_map do |name, value|
          next unless name.start_with?("file.")

          ["#{name.delete_prefix('file.')}.csv", value.downcase]
        end.to_h
      end

      # Returns an array of problem strings; empty when the manifest is usable.
      def problems
        list = []
        list << "manifest.version must be 1.0 (got #{manifest_version.inspect})" unless manifest_version == "1.0"
        unless oneroster_version == SPEC_VERSION
          list << "oneroster.version must be #{SPEC_VERSION} (got #{oneroster_version.inspect})"
        end
        declared_files.each do |file, mode|
          list << "#{file}: unknown mode #{mode.inspect} in manifest" unless MODES.include?(mode)
        end
        list
      end
    end
  end
end

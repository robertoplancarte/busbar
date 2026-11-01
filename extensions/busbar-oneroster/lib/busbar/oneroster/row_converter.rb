# frozen_string_literal: true

module Busbar
  module OneRoster
    # Turns one raw CSV row of a OneRoster file into typed BusBar field data, the
    # row action, and any errors. The engine calls this as the `oneroster_row`
    # transform; it is plain Ruby so it can be tested without Rails.
    class RowConverter
      Result = Struct.new(:data, :action, :errors, keyword_init: true) do
        def valid? = errors.empty?
      end

      attr_reader :spec, :mode

      # mode: "bulk" or "delta", from the package manifest
      def initialize(spec, mode:)
        raise ArgumentError, "mode must be bulk or delta" unless %w[bulk delta].include?(mode)

        @spec = spec
        @mode = mode
      end

      # raw: { "sourcedId" => "u1", "givenName" => "Ada", ... }
      def call(raw)
        errors = {}
        data = {}

        spec.columns.each do |column|
          field = spec.field_name(column)
          data[field] = convert(column, raw[column])
        rescue ValueError => e
          errors[field] = e.message
          data[field] = raw[column]
        end

        (["sourcedId"] + spec.required).each do |column|
          field = spec.field_name(column)
          next if errors.key?(field)

          value = data[field]
          errors[field] = "is required" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end

        action = row_action(raw, errors)
        Result.new(data: data, action: action, errors: errors)
      end

      private

      def convert(column, value)
        case column
        when "status" then Values.enum(value, STATUS_VALUES)
        when "dateLastModified" then Values.datetime(value)
        when *spec.multi_value then Values.multi_value(value)
        when *spec.dates then Values.date(value)
        when *spec.booleans then Values.boolean(value)
        when *spec.years then Values.year(value)
        else
          if (allowed = spec.enums[column])
            Values.enum(value, allowed)
          else
            Values.blank?(value) ? nil : value.strip
          end
        end
      end

      # Bulk: every row is an upsert; status and dateLastModified must be empty,
      # and records missing from the file are deactivated by the load mode.
      # Delta: status decides; tobedeleted rows deactivate the record.
      def row_action(raw, errors)
        status = raw["status"].to_s.strip
        modified = raw["dateLastModified"].to_s.strip

        if mode == "bulk"
          errors["status"] = "must be empty in a bulk file" unless status.empty?
          errors["date_last_modified"] = "must be empty in a bulk file" unless modified.empty?
          return :upsert
        end

        errors["status"] ||= "is required in a delta file" if status.empty?
        errors["date_last_modified"] ||= "is required in a delta file" if modified.empty?
        status == "tobedeleted" ? :deactivate : :upsert
      end
    end
  end
end

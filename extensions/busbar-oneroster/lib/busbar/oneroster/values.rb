# frozen_string_literal: true

require "date"
require "time"

module Busbar
  module OneRoster
    # Strict parsers for OneRoster value formats. Each returns nil for a blank
    # value and raises ValueError with a client-readable message otherwise.
    module Values
      DATE = /\A\d{4}-\d{2}-\d{2}\z/
      DATETIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z\z/
      YEAR = /\A\d{4}\z/

      module_function

      def blank?(value) = value.nil? || value.to_s.strip.empty?

      # "a,b, c" -> ["a", "b", "c"]. RFC 4180 quoting has already been removed
      # by the CSV parser, so a plain split is correct here.
      def multi_value(value)
        return [] if blank?(value)

        value.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def date(value)
        return nil if blank?(value)
        raise ValueError, "#{value.inspect} is not a YYYY-MM-DD date" unless DATE.match?(value.strip)

        Date.iso8601(value.strip)
      rescue Date::Error
        raise ValueError, "#{value.inspect} is not a valid calendar date"
      end

      def datetime(value)
        return nil if blank?(value)
        unless DATETIME.match?(value.strip)
          raise ValueError, "#{value.inspect} is not a UTC timestamp like 2026-01-31T18:25:43.511Z"
        end

        Time.iso8601(value.strip)
      rescue ArgumentError
        raise ValueError, "#{value.inspect} is not a valid timestamp"
      end

      def boolean(value)
        return nil if blank?(value)

        case value.strip
        when "true" then true
        when "false" then false
        else raise ValueError, "#{value.inspect} must be true or false"
        end
      end

      def year(value)
        return nil if blank?(value)
        raise ValueError, "#{value.inspect} is not a YYYY year" unless YEAR.match?(value.strip)

        value.strip.to_i
      end

      # OneRoster vocabularies may be extended with terms that start with "ext:".
      def enum(value, allowed)
        return nil if blank?(value)

        v = value.strip
        return v if allowed.include?(v) || v.start_with?("ext:")

        raise ValueError, "#{v.inspect} is not one of #{allowed.join(', ')} (or an ext: term)"
      end
    end
  end
end

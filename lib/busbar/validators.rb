module Busbar
  # Field validators return an error message or nil. Row rules (date_order)
  # return a list of [field, message] pairs. unique_in_file and references
  # need the whole file, so FileChecksJob runs them in SQL after staging.
  module Validators
    class Required
      def self.call(value, _args, _field) = value.nil? || value.to_s.strip.empty? ? "is required" : nil
    end

    class Format
      def self.call(value, args, _field)
        pattern = Regexp.new(args.is_a?(Hash) ? args[:with].to_s : args.to_s)
        pattern.match?(value.to_s) ? nil : "is not in the expected format"
      end
    end

    class Length
      def self.call(value, args, _field)
        length = value.to_s.length
        return "is too short (minimum #{args[:minimum]})" if args[:minimum] && length < args[:minimum]
        return "is too long (maximum #{args[:maximum]})" if args[:maximum] && length > args[:maximum]

        nil
      end
    end

    class Range
      def self.call(value, args, _field)
        return "must be at least #{args[:min]}" if !args[:min].nil? && value < args[:min]
        return "must be at most #{args[:max]}" if !args[:max].nil? && value > args[:max]

        nil
      end
    end

    class Enum
      def self.call(value, args, _field)
        allowed = Array(args.is_a?(Hash) ? args[:values] : args).map(&:to_s)
        allowed.include?(value.to_s) ? nil : "must be one of #{allowed.join(", ")}"
      end
    end

    # Rule: one date field must not come after another.
    class DateOrder
      def self.call(data, args)
        before = data[args[:before].to_s]
        after = data[args[:after].to_s]
        return [] unless before.respond_to?(:to_date) && after.respond_to?(:to_date)

        after < before ? [ [ args[:after].to_s, "must not be before #{args[:before]}" ] ] : []
      end
    end

    # Markers: checked set-based by FileChecksJob, not per row.
    class UniqueInFile
      def self.call(*) = nil
    end

    class References
      def self.call(*) = nil
    end

    BUILT_IN = {
      "required" => Required, "format" => Format, "length" => Length, "range" => Range,
      "enum" => Enum, "date_order" => DateOrder, "unique_in_file" => UniqueInFile,
      "references" => References
    }.freeze
  end
end

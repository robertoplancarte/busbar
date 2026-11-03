require "bigdecimal"

module Busbar
  # Field types cast a staged string into a Ruby value, or raise Invalid with a
  # message for the row's error list. Blank values never reach a type; the
  # required validator handles them.
  module Types
    class Invalid < StandardError; end

    class Base
      def self.cast(value, field) = new.cast(value, field)
      def cast(value, _field) = value
    end

    # Leading and trailing spaces are never meaningful in client files.
    class String < Base
      def cast(value, _field) = value.to_s.strip
    end

    class Integer < Base
      def cast(value, _field)
        return value if value.is_a?(::Integer)

        Kernel.Integer(value.to_s.delete(",_ "), 10)
      rescue ArgumentError
        raise Invalid, "is not a whole number"
      end
    end

    class Decimal < Base
      def cast(value, _field)
        BigDecimal(value.to_s.delete(",_ "))
      rescue ArgumentError
        raise Invalid, "is not a number"
      end
    end

    class Money < Decimal
      def cast(value, field)
        text = value.to_s.strip
        negative = text.start_with?("(") && text.end_with?(")")
        amount = super(text.gsub(/[^\d.\-]/, ""), field)
        negative ? -amount : amount
      end
    end

    class Boolean < Base
      TRUE = %w[true t yes y 1 on x].freeze
      FALSE = %w[false f no n 0 off].freeze

      def cast(value, _field)
        return value if value == true || value == false

        text = value.to_s.strip.downcase
        return true if TRUE.include?(text)
        return false if FALSE.include?(text)

        raise Invalid, "is not yes or no"
      end
    end

    class Date < Base
      def cast(value, field)
        return value if value.is_a?(::Date)

        format = field.options[:format]
        format ? ::Date.strptime(value.to_s, format) : ::Date.parse(value.to_s)
      rescue ::Date::Error
        raise Invalid, "is not a date#{" in #{format}" if format}"
      end
    end

    class Datetime < Base
      def cast(value, _field)
        return value if value.is_a?(::Time) || value.is_a?(::DateTime)

        ::Time.zone.parse(value.to_s) || raise(Invalid, "is not a date and time")
      rescue ArgumentError
        raise Invalid, "is not a date and time"
      end
    end

    class Email < Base
      FORMAT = URI::MailTo::EMAIL_REGEXP

      # Normalized the way most hosts store emails (locke: strip, downcase),
      # so the natural key matches what the model would save.
      def cast(value, _field)
        email = value.to_s.strip.downcase
        raise Invalid, "is not an email address" unless FORMAT.match?(email)

        email
      end
    end

    class Phone < Base
      def cast(value, _field)
        text = value.to_s.strip
        digits = text.gsub(/\D/, "")
        raise Invalid, "is not a phone number" unless digits.length.between?(7, 15)

        text.start_with?("+") ? "+#{digits}" : digits
      end
    end

    class Enum < Base
      def cast(value, field)
        allowed = Array(field.options[:values]).map(&:to_s)
        match = allowed.find { |v| v.casecmp?(value.to_s.strip) }
        match || raise(Invalid, "must be one of #{allowed.join(", ")}")
      end
    end

    # Accepts Rails names ("Eastern Time (US & Canada)") and IANA names
    # ("America/New_York"), and stores the IANA name, which is what
    # ActiveSupport::TimeZone[...] and browsers both understand.
    class TimeZone < Base
      def cast(value, _field)
        text = value.to_s.strip
        zone = ActiveSupport::TimeZone[text] ||
          ActiveSupport::TimeZone.all.find { |z| z.name.casecmp?(text) || z.tzinfo.name.casecmp?(text) }
        raise Invalid, "isn't a time zone we know" unless zone

        ActiveSupport::TimeZone[text]&.tzinfo&.name || zone.tzinfo.name
      end
    end

    BUILT_IN = {
      "string" => String, "integer" => Integer, "decimal" => Decimal, "money" => Money,
      "boolean" => Boolean, "date" => Date, "datetime" => Datetime, "email" => Email,
      "phone" => Phone, "enum" => Enum, "time_zone" => TimeZone
    }.freeze
  end
end

module Busbar
  # Transforms run before casting, on staged strings. Each one gets the field's
  # current value, its args, and a context with the whole row (`data`) and the
  # template's value maps, and returns the new value.
  module Transforms
    Context = Struct.new(:data, :value_maps, :field, keyword_init: true)

    class Strip
      def self.call(value, _args, _ctx) = value.is_a?(::String) ? value.strip : value
    end

    class Downcase
      def self.call(value, _args, _ctx) = value&.to_s&.downcase
    end

    class Upcase
      def self.call(value, _args, _ctx) = value&.to_s&.upcase
    end

    class Titleize
      def self.call(value, _args, _ctx) = value&.to_s&.titleize
    end

    class ParseDate
      def self.call(value, args, _ctx)
        return value if value.nil? || value.to_s.strip.empty?

        ::Date.strptime(value.to_s.strip, args.fetch(:format)).iso8601
      rescue ::Date::Error
        value # left for the date type to reject with a row error
      end
    end

    class ParseBoolean
      def self.call(value, _args, _ctx)
        Types::Boolean.cast(value, nil)
      rescue Types::Invalid
        value
      end
    end

    class NormalizePhone
      def self.call(value, _args, _ctx)
        return value if value.nil?

        Types::Phone.cast(value, nil)
      rescue Types::Invalid
        value
      end
    end

    # Takes one part of a value: {"separator": " ", "index": 0}
    class Split
      def self.call(value, args, _ctx)
        return value if value.nil?

        value.to_s.split(args.fetch(:separator, " ")).map(&:strip)[args.fetch(:index, 0).to_i]
      end
    end

    # Joins other fields into this one: {"fields": ["first_name", "last_name"],
    # "separator": " ", "only_blank": true}. With only_blank, a value the file
    # already has for this field wins.
    class Concat
      def self.call(value, args, ctx)
        return value if args[:only_blank] && !value.to_s.strip.empty?

        parts = Array(args.fetch(:fields)).map { |f| ctx.data[f.to_s].to_s.strip }.reject(&:empty?)
        parts.empty? ? value : parts.join(args.fetch(:separator, " "))
      end
    end

    class Default
      def self.call(value, args, _ctx)
        value.nil? || value.to_s.strip.empty? ? args.fetch(:value) : value
      end
    end

    # Looks the value up in the template's value_maps for this field, case
    # insensitively: {"status" => {"Active" => "active", "A" => "active"}}.
    class ValueMap
      def self.call(value, _args, ctx)
        map = ctx.value_maps.to_h[ctx.field.to_s] || {}
        return value if value.nil?

        hit = map.find { |source, _| source.to_s.strip.casecmp?(value.to_s.strip) }
        hit ? hit.last : value
      end
    end

    BUILT_IN = {
      "strip" => Strip, "downcase" => Downcase, "upcase" => Upcase, "titleize" => Titleize,
      "parse_date" => ParseDate, "parse_boolean" => ParseBoolean, "normalize_phone" => NormalizePhone,
      "split" => Split, "concat" => Concat, "default" => Default, "value_map" => ValueMap
    }.freeze
  end
end

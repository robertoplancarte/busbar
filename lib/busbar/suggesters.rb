module Busbar
  # Mapping suggesters, chained; the first confident answer per header wins
  # and a person always confirms on the mapping screen.
  class Suggester
    # returns [{ source:, field:, confidence:, reason: }, ...]
    def suggest(headers:, samples:, schema:) = raise(NotImplementedError)

    def self.normalize(text) = text.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  module Suggesters
    class Exact < Suggester
      def suggest(headers:, samples:, schema:)
        by_name = schema.fields.values.index_by { |f| Suggester.normalize(f.name) }
        headers.filter_map do |h|
          field = by_name[Suggester.normalize(h)]
          { source: h, field: field.name, confidence: 1.0, reason: "same name" } if field
        end
      end
    end

    class Synonyms < Suggester
      def suggest(headers:, samples:, schema:)
        index = schema.fields.values.each_with_object({}) do |f, out|
          ([ f.name, f.label ] + f.synonyms).each { |s| out[Suggester.normalize(s)] ||= f }
        end
        headers.filter_map do |h|
          field = index[Suggester.normalize(h)]
          { source: h, field: field.name, confidence: 0.9, reason: "synonym" } if field
        end
      end
    end

    DEFAULT = [ Exact, Synonyms ].freeze

    # header => field, never mapping two headers to one field.
    def self.suggest(headers:, samples:, schema:)
      chain = Array(Busbar.config.mapping_suggester.presence || DEFAULT)
      taken = {}
      chain.each do |suggester|
        suggester = suggester.new if suggester.is_a?(Class)
        suggester.suggest(headers: headers - taken.keys, samples: samples, schema: schema).each do |s|
          next if taken.key?(s[:source]) || taken.value?(s[:field])

          taken[s[:source]] = s[:field]
        end
      end
      taken
    end
  end
end

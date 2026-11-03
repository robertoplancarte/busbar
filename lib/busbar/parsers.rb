module Busbar
  # Turns a received file into rows of header => string. Every parser
  # streams except JSON arrays, which phase 1 reads whole (see docs/spec.md).
  module Parsers
    class UnsupportedFormat < Error; end

    SNIFF_BYTES = 64 * 1024
    DELIMITERS = [ ",", "\t", ";", "|" ].freeze

    # Picks a parser from the content first and the extension second.
    def self.for(path, filename: File.basename(path.to_s), options: {})
      format = options["format"].presence || detect_format(path, filename)
      case format
      when "csv", "tsv" then Csv.new(path, options)
      when "xlsx" then Xlsx.new(path, options)
      when "json" then Json.new(path, options)
      when "ndjson" then Ndjson.new(path, options)
      else raise UnsupportedFormat, "#{filename} is not a CSV, TSV, XLSX, JSON or NDJSON file"
      end
    end

    def self.detect_format(path, filename)
      head = File.binread(path, SNIFF_BYTES) || ""
      ext = File.extname(filename.to_s).delete(".").downcase
      return "xlsx" if head.start_with?("PK\x03\x04".b)
      raise UnsupportedFormat, "#{filename} looks like a binary file" if head.include?("\x00") && !utf16?(head)

      text = head.dup.force_encoding("UTF-8").scrub.delete_prefix("\uFEFF").lstrip
      return "ndjson" if %w[ndjson jsonl].include?(ext)
      return ndjson?(text) ? "ndjson" : "json" if text.start_with?("{", "[")
      return "tsv" if ext == "tsv"

      "csv"
    end

    def self.utf16?(head) = head.start_with?("\xFF\xFE".b, "\xFE\xFF".b)

    def self.ndjson?(text)
      lines = text.lines.map(&:strip).reject(&:empty?).first(2)
      lines.size == 2 && lines.all? { |l| l.start_with?("{") && l.end_with?("}") }
    end

    # Flattens nested objects into dot paths: {"address" => {"city" => "X"}}
    # becomes {"address.city" => "X"}. Arrays stay as JSON text.
    def self.flatten(hash, prefix = nil)
      hash.each_with_object({}) do |(k, v), out|
        key = prefix ? "#{prefix}.#{k}" : k.to_s
        case v
        when Hash then out.merge!(flatten(v, key))
        when Array then out[key] = v.to_json
        else out[key] = v.nil? ? nil : v.to_s
        end
      end
    end

    class Base
      attr_reader :path, :options

      def initialize(path, options = {})
        @path = path
        @options = options.to_h.stringify_keys
      end

      # First `limit` rows, for mapping samples.
      def sample(limit = 20) = each_row.lazy.first(limit)

      def headers = @headers ||= (each_row.first&.first&.keys || [])

      def detected = {}
    end

    class Csv < Base
      def each_row
        return enum_for(:each_row) unless block_given?

        header_row = options.fetch("header_row", 1).to_i
        skip_blank = options.fetch("skip_blank_rows", true)
        headers = nil
        number = 0
        File.open(path, "r:#{encoding}:UTF-8") do |io|
          io.rewind unless io.getc == "\uFEFF"
          CSV.new(io, col_sep: delimiter, liberal_parsing: true).each do |fields|
            number += 1
            next if number < header_row
            next @headers = headers = fields.map { |h| h.to_s.strip } if headers.nil?
            next if skip_blank && fields.all? { |f| f.to_s.strip.empty? }

            yield headers.each_with_index.to_h { |h, i| [ h, fields[i] ] }, number
          end
        end
      end

      def encoding
        @encoding ||= options["encoding"].presence || begin
          head = File.binread(path, SNIFF_BYTES) || ""
          if Parsers.utf16?(head) then head.start_with?("\xFF\xFE".b) ? "UTF-16LE" : "UTF-16BE"
          elsif head.dup.force_encoding("UTF-8").valid_encoding? || truncated_utf8?(head) then "UTF-8"
          else "Windows-1252"
          end
        end
      end

      def delimiter
        @delimiter ||= options["delimiter"].presence || begin
          first = File.open(path, "r:#{encoding}:UTF-8", &:gets).to_s
          File.extname(path.to_s) == ".tsv" ? "\t" : DELIMITERS.max_by { |d| first.count(d) }
        end
      end

      def detected = { "encoding" => encoding, "delimiter" => delimiter }

      private

      # A multi-byte character cut at the end of the sniffed bytes.
      def truncated_utf8?(head)
        (1..3).any? { |n| head.byteslice(0, head.bytesize - n).force_encoding("UTF-8").valid_encoding? }
      end
    end

    class Ndjson < Base
      def each_row
        return enum_for(:each_row) unless block_given?

        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
          line = line.delete_prefix("\uFEFF").strip
          next if line.empty?

          yield Parsers.flatten(JSON.parse(line)), number
        end
      end
    end

    class Json < Base
      def each_row(&block)
        return enum_for(:each_row) unless block_given?

        records.each.with_index(1) { |record, number| yield Parsers.flatten(record), number }
      end

      private

      def records
        doc = JSON.parse(File.read(path, encoding: "UTF-8").delete_prefix("\uFEFF"))
        return doc if doc.is_a?(Array)

        path = options["json_path"].presence
        found = path ? doc.dig(*path.split(".")) : doc.values.find { |v| v.is_a?(Array) }
        raise UnsupportedFormat, "JSON must be an array of objects, or an object with one array" unless found.is_a?(Array)

        found
      end
    end

    class Xlsx < Base
      def each_row
        return enum_for(:each_row) unless block_given?

        require "roo"
        header_row = options.fetch("header_row", 1).to_i
        headers = nil
        sheet = Roo::Excelx.new(path.to_s, file_warning: :ignore)
        sheet.each_row_streaming(pad_cells: true).with_index(1) do |cells, number|
          values = cells.map { |c| cell_text(c) }
          next if number < header_row
          next @headers = headers = values.map { |h| h.to_s.strip } if headers.nil?
          next if values.all? { |v| v.to_s.strip.empty? }

          yield headers.each_with_index.to_h { |h, i| [ h, values[i] ] }, number
        end
      end

      private

      def cell_text(cell)
        value = cell&.value
        case value
        when nil then nil
        when Float then value == value.floor ? value.to_i.to_s : value.to_s
        when Date, Time, DateTime then value.iso8601
        else value.to_s
        end
      end
    end
  end
end

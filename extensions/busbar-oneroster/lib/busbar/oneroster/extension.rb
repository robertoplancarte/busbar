# frozen_string_literal: true

module Busbar
  module OneRoster
    # Registers OneRoster with the BusBar engine through its extension API.
    # Loaded only when the engine fires `ActiveSupport.run_load_hooks(:busbar)`,
    # so the rest of this gem works (and is tested) without Rails.
    module Extension
      module_function

      def register!(busbar = ::Busbar)
        busbar.register_extension(:oneroster, version: VERSION) do |ext|
          ext.transform :oneroster_row, RowTransform
          ext.package_handler PackageHandler

          FILE_SPECS.each do |spec|
            register_schema(ext, spec)
            register_template(ext, spec)
          end
        end
      end

      # One BusBar schema per OneRoster file. Values are typed by the
      # oneroster_row transform, so fields are declared loosely here and
      # references let the engine's set-based check catch dangling sourcedIds.
      def register_schema(ext, spec)
        ext.schema :"oneroster_#{spec.schema}" do |s|
          s.natural_key :sourced_id
          s.scope_key :source_system # bulk deactivation only touches this SIS's records

          spec.columns.each do |column|
            field = spec.field_name(column)
            options = {}
            options[:required] = true if column == "sourcedId" || spec.required.include?(column)
            options[:references] = :"oneroster_#{spec.references[column]}" if spec.references[column]
            s.field field, field_type(spec, column), **options
          end
          s.field :source_system, :string
        end
      end

      # Headers are fixed by the standard, so every file gets a ready-made
      # template and runs skip the Awaiting mapping step.
      def register_template(ext, spec)
        ext.template :"oneroster_#{spec.schema}",
                     schema: :"oneroster_#{spec.schema}",
                     column_map: spec.columns.to_h { |c| [c, spec.field_name(c)] },
                     transforms: [{ step: :oneroster_row, args: { file: spec.file } }],
                     options: { header_row: 1, delimiter: ",", encoding: "UTF-8" }
      end

      def field_type(spec, column)
        return :datetime if column == "dateLastModified"
        return :array if spec.multi_value.include?(column)
        return :date if spec.dates.include?(column)
        return :boolean if spec.booleans.include?(column)
        return :integer if spec.years.include?(column)

        :string
      end
    end

    # Engine transform: types the whole row in one step and sets its action.
    # The engine passes a staged row (raw, data, errors, action) and a context
    # whose package entry carries the file's bulk/delta mode.
    class RowTransform
      def initialize(file:)
        @spec = OneRoster.file_spec(file) or raise ArgumentError, "unknown OneRoster file #{file}"
      end

      def call(row, context)
        mode = context.package_entry.metadata.fetch(:mode)
        result = RowConverter.new(@spec, mode: mode).call(row.raw)
        row.data.merge!(result.data)
        row.data["source_system"] = context.package.metadata[:source_system]
        result.errors.each { |field, message| row.add_error(field, message) }
        row.action = result.action # :upsert or :deactivate
      end
    end

    # Engine package handler: recognises a OneRoster zip and expands it into one
    # child run per file, in dependency order.
    class PackageHandler
      def self.match?(path, filename:)
        File.extname(filename.to_s).casecmp?(".zip") && PackageReader.package?(path)
      end

      def initialize(path, **)
        @path = path
      end

      # Returns the plan the engine turns into child runs. Bulk files use the
      # snapshot_deactivate load mode, scoped to the source system, which matches
      # the binding's rule that records missing from a bulk file become
      # tobedeleted. Delta files load incrementally and deactivate per row.
      def open
        @package = PackageReader.new(@path).read
        {
          metadata: { source_system: @package.source_system },
          warnings: @package.warnings,
          children: @package.entries.map do |entry|
            {
              schema: :"oneroster_#{entry.schema}",
              template: :"oneroster_#{entry.schema}",
              path: entry.path,
              filename: entry.file,
              row_count: entry.row_count,
              load_mode: entry.mode == "bulk" ? :snapshot_deactivate : :incremental,
              metadata: { mode: entry.mode }
            }
          end
        }
      rescue PackageError => e
        { errors: e.problems }
      end

      def close
        @package&.close
      end
    end
  end
end

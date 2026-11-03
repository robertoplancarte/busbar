module Busbar
  # Checksum, format and encoding detection, headers, row count and 20
  # sample values per column. Stops at awaiting_mapping when the run has no
  # template; otherwise moves straight on to staging.
  class PrepareJob < ApplicationJob
    SAMPLE_SIZE = 20

    def perform(run_id)
      run = find_run(run_id)
      return unless run.can_transition_to?(:preparing)

      run.transition_to!(:preparing)
      run.update!(started_at: run.started_at || Time.current)
      run.file.open do |file|
        parser = Parsers.for(file.path, filename: run.filename, options: run.parse_options)
        samples = Hash.new { |h, k| h[k] = [] }
        count = 0
        parser.each_row do |row, _|
          count += 1
          next if count > SAMPLE_SIZE

          row.each { |header, value| samples[header] << value unless value.to_s.strip.empty? }
        end
        headers = parser.headers
        run.update!(
          checksum: Digest::SHA256.file(file.path).hexdigest, row_count: count,
          options: run.options.to_h.merge("headers" => headers, "samples" => samples.slice(*headers),
                                          "detected" => parser.detected,
                                          "suggestions" => Suggesters.suggest(headers: headers, samples: samples, schema: run.schema))
        )
      end

      if run.template && run.column_map.present?
        run.transition_to!(:staging)
        StageJob.perform_later(run.id)
      else
        run.transition_to!(:awaiting_mapping)
      end
    rescue Parsers::UnsupportedFormat, CSV::MalformedCSVError, JSON::ParserError => e
      fail_run!(run, e)
    end
  end
end

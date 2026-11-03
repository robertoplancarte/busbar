module Busbar
  # Streams the file, applies the column map and bulk-writes staged rows, one
  # insert per chunk. Re-running clears the run's staged rows first.
  class StageJob < ApplicationJob
    def perform(run_id)
      run = find_run(run_id)
      return unless run.in_state?(:staging)

      run.staged_rows.delete_all
      chunk_size = Busbar.config.chunk_size
      column_map = run.column_map.compact_blank
      buffer = []
      chunk = 0
      total = 0
      run.file.open do |file|
        Parsers.for(file.path, filename: run.filename, options: run.parse_options).each_row do |row, number|
          data = column_map.each_with_object({}) { |(header, field), out| out[field] = row[header] }
          buffer << { tenant_id: run.tenant_id, run_id: run.id, chunk: chunk, row_number: number, raw: row, data: data, status: "pending" }
          total += 1
          next if buffer.size < chunk_size

          StagedRow.insert_all!(buffer)
          buffer.clear
          chunk += 1
        end
      end
      StagedRow.insert_all!(buffer) if buffer.any?
      chunk_count = (total.to_f / chunk_size).ceil
      run.update!(row_count: total, chunk_count: chunk_count, chunks_done: 0, checks_enqueued_at: nil, finalize_enqueued_at: nil)
      run.transition_to!(:validating)
      if chunk_count.zero?
        run.claim!(:checks_enqueued_at) && FileChecksJob.perform_later(run.id)
      else
        chunk_count.times { |c| ValidateChunkJob.perform_later(run.id, c) }
      end
    end
  end
end

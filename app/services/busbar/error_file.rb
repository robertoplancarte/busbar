module Busbar
  # The downloadable error CSV: the client's own columns, row number and an
  # Errors column, streamed from staged rows. Cells that look like formulas
  # are escaped against CSV injection.
  module ErrorFile
    module_function

    FORMULA = /\A[=+\-@\t\r]/

    def attach(run)
      tempfile = Tempfile.new([ "busbar-errors-#{run.id}", ".csv" ])
      write(run, tempfile)
      tempfile.rewind
      run.error_file.attach(io: tempfile, filename: "#{File.basename(run.filename.to_s, ".*")}-errors.csv", content_type: "text/csv")
    ensure
      tempfile&.close!
    end

    def write(run, io)
      headers = run.headers
      io.write(CSV.generate_line([ "Row", *headers, "Errors" ].map { |c| escape(c) }))
      run.staged_rows.with_errors.order(:row_number).find_each do |row|
        errors = row.errors_list.map { |e| "#{e["field"]} #{e["message"]}" }.join("; ")
        io.write(CSV.generate_line([ row.row_number, *headers.map { |h| row.raw[h] }, errors ].map { |c| escape(c) }))
      end
    end

    def escape(value)
      text = value.to_s
      FORMULA.match?(text) ? "'#{text}" : text
    end
  end
end

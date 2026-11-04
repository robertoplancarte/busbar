module Busbar
  # One row of a run, as received (`raw`), mapped and cast (`data`), with its
  # errors, its diff action and, after loading, the host record id.
  #
  # status: pending -> valid | invalid -> loaded | failed
  # action: create | update | unchanged | skip (set by DiffJob, then by the loader's outcome)
  class StagedRow < ApplicationRecord
    self.table_name = "busbar_staged_rows"
    busbar_tenant_scoped

    belongs_to :run, class_name: "Busbar::Run"

    scope :with_errors, -> { where(status: %w[invalid failed]) }

    def errors_list = Array(row_errors)

    def natural_key_values = Array(natural_key)

    # The host record this row created or updated, through the loader's model.
    def record
      return @record if defined?(@record)

      @record = record_id && run.loader.scope(run.loader_context).find_by(run.loader.model.primary_key => record_id)
    end
  end
end

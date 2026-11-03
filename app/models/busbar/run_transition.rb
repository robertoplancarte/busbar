module Busbar
  # Statesman's history of a run's states: who moved it, when, and why.
  # metadata is jsonb, so Statesman's ActiveRecordTransition (which adds a
  # JSON `serialize`) is left out, as Statesman's docs say for json columns.
  class RunTransition < ApplicationRecord
    self.table_name = "busbar_run_transitions"
    class_attribute :updated_timestamp_column, default: :updated_at

    belongs_to :run, class_name: "Busbar::Run", inverse_of: :transitions

    after_destroy :update_most_recent, if: :most_recent?

    private

    def update_most_recent
      last = run.transitions.order(:sort_key).last
      last&.update_column(:most_recent, true)
    end
  end
end

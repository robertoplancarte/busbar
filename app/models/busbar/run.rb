module Busbar
  # One file on its way into the host app. See RunStateMachine for states and
  # the jobs under app/jobs/busbar for each stage.
  class Run < ApplicationRecord
    self.table_name = "busbar_runs"
    busbar_tenant_scoped

    belongs_to :template, class_name: "Busbar::Template", optional: true
    has_many :transitions, class_name: "Busbar::RunTransition", autosave: false, dependent: :delete_all, inverse_of: :run
    has_many :staged_rows, class_name: "Busbar::StagedRow", dependent: :delete_all
    has_one_attached :file
    has_one_attached :error_file

    validates :schema_key, presence: true
    validates :load_mode, inclusion: { in: Template::LOAD_MODES }

    delegate :can_transition_to?, :current_state, :history, :last_transition, :in_state?, to: :state_machine

    def state_machine
      @state_machine ||= RunStateMachine.new(self, transition_class: RunTransition, association_name: :transitions)
    end

    # Records the user (if any) and any extra metadata on the transition.
    def transition_to!(state, user: nil, **metadata)
      state_machine.transition_to!(state, metadata.merge(user_id: user&.id).compact)
    end

    def finished? = RunStateMachine::FINISHED.include?(state)

    def schema = Busbar.schema(schema_key)
    def loader = @loader ||= Busbar.loader_for(schema)

    def column_map = template_snapshot.to_h.fetch("column_map", {})
    def template_transforms = template_snapshot.to_h.fetch("transforms", [])
    def value_maps = template_snapshot.to_h.fetch("value_maps", {})
    def parse_options = template_snapshot.to_h.fetch("options", {}).to_h.merge(options.to_h.slice("format"))
    def natural_key = template_snapshot.to_h.fetch("natural_key") { schema.natural_key_for(column_map.values) }

    def headers = options.to_h.fetch("headers", [])
    def samples = options.to_h.fetch("samples", {})
    def suggestions = options.to_h.fetch("suggestions", {})

    # Fields this run writes: the schema's loadable fields the template maps
    # or a transform fills in.
    def loadable_fields
      targets = column_map.values + (template_transforms + schema.transforms).map { |t| t.to_h.stringify_keys["field"] }
      schema.loadable_fields & targets.compact.map(&:to_s)
    end

    # What the loader writes for one row. Blank cells are left out, so they
    # never clear a value the record already has.
    def loadable_data(data) = data.to_h.slice(*loadable_fields).compact

    def loader_context
      Loader::Context.new(tenant: tenant, run: self, load_mode: load_mode, natural_key: natural_key, user: approved_by)
    end

    def created_by = user_for(created_by_id)
    def approved_by = user_for(approved_by_id)

    def counts
      { "created" => created_count, "updated" => updated_count, "unchanged" => unchanged_count,
        "skipped" => skipped_count, "invalid" => invalid_count, "failed" => failed_count }
    end

    # Pins the template the run uses; called by Runs.create_from and on
    # mapping confirmation.
    def use_template!(template)
      update!(template: template, template_snapshot: template.snapshot, template_version: template.version,
              load_mode: template.load_mode)
    end

    # Takes the per-run counter one step forward, atomically, and returns the new value.
    def increment_chunks_done!
      self.class.connection.select_value(
        self.class.sanitize_sql([ "UPDATE busbar_runs SET chunks_done = chunks_done + 1 WHERE id = ? RETURNING chunks_done", id ])
      ).to_i
    end

    # True for exactly one caller: the first to claim `column` for this run.
    # Chunk jobs use it so only one of them enqueues the next stage.
    def claim!(column)
      self.class.where(id: id, column => nil).update_all(column => Time.current) == 1
    end

    private

    def user_for(id)
      return if id.nil?

      Busbar.config.user_class&.constantize&.find_by(id: id)
    end
  end
end

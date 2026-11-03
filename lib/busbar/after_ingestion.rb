module Busbar
  # The host's hook for side effects once a run has loaded: invitations,
  # search reindexing, billing. Called once per run inside
  # Busbar::AfterIngestionJob with the run's tenant set. The engine itself
  # never sends email.
  #
  #   class UserIngestionHandler < Busbar::AfterIngestion
  #     def call(run, context)
  #       context.created.each do |row|
  #         UserMailer.with(user: row.record).invitation_instructions.deliver_later
  #       end
  #     end
  #   end
  #
  # Idempotent by default: `context.created.each` (and updated, unchanged,
  # failed) streams rows in batches and marks each row handled once the block
  # returns for it, so a retried or re-run handler skips rows it already
  # handled and nobody gets a second invitation. Use `.all` for the plain
  # scope with no bookkeeping.
  class AfterIngestion
    def call(_run, _context) = nil

    class Context
      attr_reader :run, :tenant, :deactivated_keys

      def initialize(run)
        @run = run
        @tenant = run.tenant
        @deactivated_keys = Array(run.deactivated_keys)
      end

      def created = RowSet.new(run, "create")
      def updated = RowSet.new(run, "update")
      def unchanged = RowSet.new(run, "unchanged")
      def failed = RowSet.new(run, nil, status: "failed")

      def template = run.template
      def user = run.approved_by
      def run_id = run.id

      # The host record for a natural key (array of values, in natural key order).
      def record(key)
        loader = run.loader
        loader.find_existing([ Array(key) ], run.loader_context).values.first
      end
    end

    class RowSet
      include Enumerable

      def initialize(run, action, status: "loaded")
        @run = run
        @action = action
        @status = status
      end

      def all
        scope = @run.staged_rows.where(status: @status)
        @action ? scope.where(action: @action) : scope
      end

      def count = all.count

      # Unhandled rows only; each is marked handled after the block succeeds.
      def each
        return enum_for(:each) unless block_given?

        all.where(handled_at: nil).find_each do |row|
          yield row
          row.update_columns(handled_at: Time.current)
        end
      end
      alias_method :find_each, :each
    end
  end
end

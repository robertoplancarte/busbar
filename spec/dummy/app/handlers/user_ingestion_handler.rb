# What locke would write: invite every user an import created. Safe to
# re-run, because context.created skips rows it already handled.
class UserIngestionHandler < Busbar::AfterIngestion
  def call(_run, context)
    context.created.each do |row|
      UserMailer.with(user: row.record).invitation_instructions.deliver_later
    end
  end
end

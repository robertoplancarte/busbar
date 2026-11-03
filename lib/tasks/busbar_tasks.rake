namespace :busbar do
  desc "Check BusBar's schemas against the host app's models and indexes"
  task check: :environment do
    findings = Busbar::InstallCheck.run
    findings.each { |f| puts f }
    puts "BusBar: all schemas look good" if findings.empty?
    exit 1 if findings.any? { |f| f.level == :error }
  end
end

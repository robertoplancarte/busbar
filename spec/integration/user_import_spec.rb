# The phase 1 target, against a User shaped like locke's: has_secure_password,
# deterministic encryption on email, create callbacks, tenant_id.
RSpec.describe "Importing users", type: :model do
  let(:acme) { create_tenant("Acme") }
  let(:globex) { create_tenant("Globex") }
  let(:map) { { "Email" => "email", "Full Name" => "name", "Time Zone" => "time_zone" } }

  it "creates users through the model, so callbacks, normalization and encryption run" do
    run = import(acme, "users.csv", column_map: map)

    expect(run.state).to eq("completed")
    expect(run.created_count).to eq(3)
    users = users_in(acme)
    expect(users.map(&:email)).to eq(%w[ana@acme.test bo@acme.test cy@acme.test])
    expect(users.map(&:name)).to eq([ "Ana Lima", "Bo Diaz", "Cy Young" ])
    expect(users.map(&:time_zone)).to eq(%w[America/Mexico_City America/New_York Etc/UTC])
    expect(users).to all(have_attributes(public_id: start_with("usr_"), otp_secret: be_present, webauthn_id: be_present,
                                         password_digest: be_present, tenant_id: acme.id))
  end

  it "stores the email key encrypted and still matches it" do
    import(acme, "users.csv", column_map: map)

    raw = User.connection.select_values("SELECT email FROM users")
    expect(raw).to all(include("\"p\":"))
    expect(raw.join).not_to include("ana@acme.test")
    ActsAsTenant.with_tenant(acme) { expect(User.where(email: "ANA@acme.test ").count).to eq(1) }
  end

  it "labels a second run create, update or unchanged by the encrypted email" do
    import(acme, "users.csv", column_map: map)
    ActsAsTenant.with_tenant(acme) { User.find_by(email: "bo@acme.test").update!(name: "Old Name") }

    run = import(acme, "users_split_names.csv", column_map: { "Work Email" => "email", "First" => "first_name", "Last" => "last_name" })
    expect(rows_of(run).map(&:action)).to eq(%w[unchanged create])

    run = import(acme, "users.csv", column_map: map)
    expect(rows_of(run).map { |r| [ r.data["email"], r.action ] }).to eq(
      [ [ "ana@acme.test", "unchanged" ], [ "bo@acme.test", "update" ], [ "cy@acme.test", "unchanged" ] ]
    )
    expect([ run.created_count, run.updated_count, run.unchanged_count ]).to eq([ 0, 1, 2 ])
    expect(users_in(acme).size).to eq(4)
  end

  it "joins first_name and last_name into name" do
    import(acme, "users_split_names.csv", column_map: { "Work Email" => "email", "First" => "first_name", "Last" => "last_name" })

    expect(users_in(acme).map(&:name)).to eq([ "Ana Lima", "Dee Moss" ])
  end

  it "stops at review with the diff, and writes nothing until approved" do
    run = import(acme, "users.csv", column_map: map, approve: false)

    expect(run.state).to eq("ready")
    expect(rows_of(run).map(&:action)).to eq(%w[create create create])
    expect(users_in(acme)).to be_empty
  end

  it "keeps invalid rows out of the load and reports why" do
    run = import(acme, "users_invalid.csv", column_map: map)

    expect(run.state).to eq("completed_with_errors")
    errors = rows_of(run).to_h { |r| [ r.row_number, r.errors_list.map { |e| "#{e["field"]} #{e["message"]}" } ] }
    expect(errors).to eq(
      2 => [ "time_zone isn't a time zone we know" ],
      3 => [ "email is not an email address" ],
      4 => [ "email is required" ],
      5 => [],
      6 => [ "email duplicates row 5" ]
    )
    expect(users_in(acme).map(&:email)).to eq(%w[ok@acme.test])
    ActsAsTenant.with_tenant(acme) do
      csv = CSV.parse(run.error_file.download, headers: true)
      expect(csv.map { |r| r["Row"] }).to eq(%w[2 3 4 6])
    end
  end

  it "puts model validation errors on the staged row as row errors" do
    Busbar.define_schema(:loose_user) do
      natural_key :email
      loader :active_record_save, model: "User"
      field :email, :string
      field :name, :string
    end
    long_name = "x" * 101
    File.write(path = Rails.root.join("tmp", "long_name.csv").to_s, "Email,Name\nlong@acme.test,#{long_name}\nfine@acme.test,Fine\n")

    run = ActsAsTenant.with_tenant(acme) do
      perform_enqueued_jobs { Busbar::Runs.create_from(path, tenant: acme, schema: :loose_user, review_required: false) }
      run = Busbar::Run.last
      perform_enqueued_jobs { Busbar::Runs.confirm_mapping(run, column_map: { "Email" => "email", "Name" => "name" }) }
      run.reload
    end

    expect(run.state).to eq("completed_with_errors")
    expect(rows_of(run).first).to have_attributes(status: "failed", row_errors: [ { "field" => "name", "message" => "is too long (maximum is 100 characters)", "validator" => "model" } ])
    expect(users_in(acme).map(&:email)).to eq([ "fine@acme.test" ])
  ensure
    Busbar.schemas.instance_variable_get(:@entries).delete("loose_user")
  end

  it "never imports passwords" do
    expect { Busbar.define_schema(:bad) { natural_key :email; field :email, :email; field :password, :string } }
      .to raise_error(Busbar::ConfigurationError, /never imports passwords/)
  end

  it "keeps tenants apart when they share an email" do
    create_user(globex, email: "ana@acme.test", name: "Globex Ana")

    import(acme, "users.csv", column_map: map)
    run = import(globex, "users.csv", column_map: map)

    expect(rows_of(run).map(&:action)).to eq(%w[update create create])
    expect(users_in(acme).size).to eq(3)
    expect(users_in(globex).map(&:name)).to eq([ "Ana Lima", "Bo Diaz", "Cy Young" ])
    ActsAsTenant.with_tenant(acme) { expect(Busbar::Run.count).to eq(1) }
  end

  it "only creates in create_only mode" do
    create_user(acme, email: "ana@acme.test", name: "Keep Me")

    run = import(acme, "users.csv", column_map: map, load_mode: "create_only")

    expect(rows_of(run).map(&:action)).to eq(%w[skip create create])
    expect(users_in(acme).first.name).to eq("Keep Me")
  end

  describe "snapshot_deactivate" do
    let(:deactivated) { [] }

    before do
      calls = deactivated
      loader = Class.new(Busbar::Loaders::ActiveRecordSave) do
        define_method(:deactivate) { |keys, context| calls << [ keys, records_for(keys, context).map(&:email) ] }
      end
      Busbar.register_loader(:user, loader)
    end

    after { Busbar.loaders.instance_variable_get(:@entries).delete("user") }

    it "hands the keys of missing users to the loader's deactivate, with no status column" do
      create_user(acme, email: "gone@acme.test")
      create_user(globex, email: "other@globex.test")

      run = import(acme, "users.csv", column_map: map, load_mode: "snapshot_deactivate")

      expect(deactivated).to eq([ [ [ [ "gone@acme.test" ] ], [ "gone@acme.test" ] ] ])
      expect(run.deactivated_keys).to eq([ [ "gone@acme.test" ] ])
    end
  end

  describe "after ingestion" do
    around do |example|
      Busbar.config.after_ingestion = { user: "UserIngestionHandler" }
      example.run
    ensure
      Busbar.config.after_ingestion = {}
    end

    it "lets the host invite each created user, once, even when re-run" do
      create_user(acme, email: "ana@acme.test")
      invited = -> { ActionMailer::Base.deliveries.map { |m| m.to.first } }
      ActionMailer::Base.deliveries.clear

      run = import(acme, "users.csv", column_map: map)
      expect(invited.call).to eq(%w[bo@acme.test cy@acme.test])

      ActsAsTenant.with_tenant(acme) { perform_enqueued_jobs { Busbar::Runs.rerun_after_ingestion(run) } }
      import(acme, "users.csv", column_map: map)

      expect(invited.call).to eq(%w[bo@acme.test cy@acme.test])
      expect(run.reload.after_ingestion_state).to eq("done")
    end

    it "carries on from the first unhandled row when a handler fails part way" do
      ActionMailer::Base.deliveries.clear
      calls = 0
      flaky = Class.new(Busbar::AfterIngestion) do
        define_method(:call) do |_run, context|
          context.created.each do |row|
            calls += 1
            raise "mail server down" if calls == 2
            UserMailer.with(user: row.record).invitation_instructions.deliver_now
          end
        end
      end
      stub_const("FlakyHandler", flaky)
      Busbar.config.after_ingestion = { user: "FlakyHandler" }

      run = import(acme, "users.csv", column_map: map)

      expect(ActionMailer::Base.deliveries.map { |m| m.to.first }).to eq(%w[ana@acme.test bo@acme.test cy@acme.test])
      expect(run.reload.after_ingestion_state).to eq("done")
    end

    it "gives the handler the created record" do
      emails = []
      handler = Class.new(Busbar::AfterIngestion) do
        define_method(:call) { |_run, context| context.created.each { |row| emails << row.record.email } }
      end
      stub_const("CollectingHandler", handler)
      Busbar.config.after_ingestion = { default: "CollectingHandler" }

      import(acme, "users.csv", column_map: map)

      expect(emails).to eq(%w[ana@acme.test bo@acme.test cy@acme.test])
    end
  end
end

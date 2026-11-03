RSpec.describe "Upload, map, review and approve", type: :request do
  include ActiveJob::TestHelper

  let(:acme) { create_tenant("Acme") }
  let(:globex) { create_tenant("Globex") }
  let(:admin) { create_user(acme, email: "admin@acme.test") }
  let(:headers) { { "X-Test-User-Id" => admin.id.to_s } }
  let(:file) { Rack::Test::UploadedFile.new(fixture_file("users.csv"), "text/csv") }

  before { host! "#{acme.subdomain}.example.com" }

  around do |example|
    saved = Busbar.config.authorize
    example.run
  ensure
    Busbar.config.authorize = saved
  end

  def allow_admins!
    # What locke can write without roles: a per-tenant admin list.
    admins = [ admin.id ]
    Busbar.config.authorize = ->(user, _action, _record) { user.present? && admins.include?(user.id) && user.tenant_id == ActsAsTenant.current_tenant&.id }
  end

  it "denies everything until the host configures authorize" do
    get "/busbar/runs", headers: headers
    expect(response).to have_http_status(:forbidden)

    post "/busbar/runs", params: { schema: "user", file: file }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it "takes a file from upload to loaded users" do
    allow_admins!

    get "/busbar/runs/new", headers: headers
    expect(response.body).to include("Users")

    perform_enqueued_jobs { post "/busbar/runs", params: { schema: "user", file: file }, headers: headers }
    run = ActsAsTenant.with_tenant(acme) { Busbar::Run.sole }
    expect(response).to redirect_to("/busbar/runs/#{run.id}")

    get "/busbar/runs/#{run.id}/mapping", headers: headers
    expect(response.body).to include("Ana Lima").and include('<option selected="selected" value="email">')

    perform_enqueued_jobs do
      patch "/busbar/runs/#{run.id}/mapping", headers: headers,
            params: { column_map: { "Email" => "email", "Full Name" => "name", "Time Zone" => "time_zone" }, template_name: "Acme HR" }
    end
    get "/busbar/runs/#{run.id}/review?filter=create", headers: headers
    expect(response.body).to include("To create: <strong>3</strong>").and include("cy@acme.test")

    perform_enqueued_jobs { patch "/busbar/runs/#{run.id}/review", headers: headers }
    get "/busbar/runs/#{run.id}", headers: headers
    expect(response.body).to include("Completed")
    expect(users_in(acme).map(&:email)).to include("ana@acme.test", "bo@acme.test", "cy@acme.test")
  end

  it "rejects a mapping that leaves the email unmapped" do
    allow_admins!
    perform_enqueued_jobs { post "/busbar/runs", params: { schema: "user", file: file }, headers: headers }
    run = ActsAsTenant.with_tenant(acme) { Busbar::Run.sole }

    patch "/busbar/runs/#{run.id}/mapping", params: { column_map: { "Full Name" => "name" } }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("leaves required fields unmapped: email")
  end

  it "does not show another tenant's runs" do
    allow_admins!
    other = ActsAsTenant.with_tenant(globex) do
      Busbar::Runs.create_from(fixture_file("users.csv"), tenant: globex, schema: :user)
    end

    get "/busbar/runs/#{other.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end
end

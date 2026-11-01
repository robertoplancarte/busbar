RSpec.describe "Engine mount" do
  it "mounts the engine under /busbar in the host" do
    route = Rails.application.routes.routes.find { |r| r.app.app == Busbar::Engine }

    expect(route.path.spec.to_s).to eq("/busbar")
  end
end

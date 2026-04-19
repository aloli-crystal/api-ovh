require "../../spec_helper"

describe OvhApi::Endpoints::Ips do
  it "liste les IPs avec reverse" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /ip\/.+\/reverse$/,
      status: 200,
      body: %(["192.0.2.10","192.0.2.11"]),
    )

    client.ips.list("192.0.2.10").should eq(["192.0.2.10", "192.0.2.11"])
  end

  it "récupère le reverse d'une IP précise" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /ip\/.+\/reverse\/192\.0\.2\.10/,
      status: 200,
      body: %({"ipReverse":"192.0.2.10","reverse":"web01.aloli.fr."}),
    )

    rev = client.ips.get_reverse("192.0.2.10", "192.0.2.10")
    rev.ip_reverse.should eq("192.0.2.10")
    rev.reverse.should eq("web01.aloli.fr.")
  end

  it "POSTe ipReverse + reverse pour définir le reverse" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "POST",
      /ip\/.+\/reverse$/,
      status: 200,
      body: %({"ipReverse":"192.0.2.10","reverse":"web01.aloli.fr."}),
    )

    rev = client.ips.set_reverse(ip: "192.0.2.10", reverse: "web01.aloli.fr.")
    rev.reverse.should eq("web01.aloli.fr.")

    req = transport.requests.find { |r| r.method == "POST" }.not_nil!
    req.body.should contain(%("ipReverse":"192.0.2.10"))
    req.body.should contain(%("reverse":"web01.aloli.fr."))
  end

  it "distingue IP de bloc et IP cible" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "POST",
      /ip\/.+\/reverse$/,
      status: 200,
      body: %({"ipReverse":"192.0.2.10","reverse":"web01.aloli.fr."}),
    )

    client.ips.set_reverse(
      ip: "192.0.2.0/24",
      ip_reverse: "192.0.2.10",
      reverse: "web01.aloli.fr.",
    )

    req = transport.requests.find { |r| r.method == "POST" }.not_nil!
    req.url.should contain("192.0.2.0")
    req.body.should contain(%("ipReverse":"192.0.2.10"))
  end

  it "DELETEe un reverse" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("DELETE", /reverse\/192/, status: 200, body: "")

    client.ips.delete_reverse("192.0.2.10", "192.0.2.10")

    transport.requests.find { |r| r.method == "DELETE" }.should_not be_nil
  end
end

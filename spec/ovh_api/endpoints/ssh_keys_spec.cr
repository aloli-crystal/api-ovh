require "../../spec_helper"

describe OvhApi::Endpoints::SshKeys do
  it "liste les clés du compte" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("GET", /me\/sshKey$/, status: 200, body: %(["laptop","desktop"]))

    client.ssh_keys.list.should eq(["laptop", "desktop"])
  end

  it "renvoie un tableau vide quand la réponse est []" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("GET", /me\/sshKey$/, status: 200, body: "[]")

    client.ssh_keys.list.should be_empty
  end

  it "récupère le détail d'une clé par nom" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /me\/sshKey\/laptop/,
      status: 200,
      body: %({"keyName":"laptop","key":"ssh-ed25519 AAAA me@host","default":true}),
    )

    key = client.ssh_keys.get("laptop")
    key.key_name.should eq("laptop")
    key.key.should eq("ssh-ed25519 AAAA me@host")
    key.default.should be_true
  end

  it "POSTe keyName/key/default à la création" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("POST", /me\/sshKey$/, status: 200, body: "")

    client.ssh_keys.create(name: "laptop", key: "ssh-ed25519 AAAA")

    req = transport.requests.find { |r| r.method == "POST" }.not_nil!
    req.body.should eq(%({"keyName":"laptop","key":"ssh-ed25519 AAAA","default":false}))
  end

  it "peut marquer la clé comme default" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("POST", /me\/sshKey/, status: 200, body: "")

    client.ssh_keys.create(name: "laptop", key: "ssh-ed25519 AAAA", default: true)

    req = transport.requests.find { |r| r.method == "POST" }.not_nil!
    req.body.should contain(%("default":true))
  end

  it "DELETEe une clé par nom" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("DELETE", /me\/sshKey\/laptop/, status: 200, body: "")

    client.ssh_keys.delete("laptop")

    transport.requests.find { |r| r.method == "DELETE" }.should_not be_nil
  end
end

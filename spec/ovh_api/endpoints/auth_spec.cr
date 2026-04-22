require "../../spec_helper"

describe OvhApi::Endpoints::Auth do
  describe "#request_consumer_key" do
    it "POST /auth/credential avec X-Ovh-Application seul (pas de HMAC)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /\/auth\/credential/,
        status: 200,
        body: %({"validationUrl":"https://eu.api.ovh.com/auth/?credentialToken=xyz","consumerKey":"CK123","state":"pendingValidation"}),
      )

      result = client.auth.request_consumer_key([
        OvhApi::Endpoints::AccessRule.new(method: "GET", path: "/dedicated/server/*"),
        OvhApi::Endpoints::AccessRule.new(method: "PUT", path: "/services/*"),
      ])

      result.consumer_key.should eq("CK123")
      result.validation_url.should eq("https://eu.api.ovh.com/auth/?credentialToken=xyz")
      result.state.should eq("pendingValidation")

      req = transport.requests.find! { |r| r.method == "POST" }
      req.url.should end_with("/auth/credential")
      # Pas de signature HMAC (app_only=true).
      req.headers["X-Ovh-Application"].should eq("app-key")
      req.headers["X-Ovh-Signature"]?.should be_nil
      req.headers["X-Ovh-Consumer"]?.should be_nil
      # Body contient la liste des règles.
      req.body.should contain(%("method":"GET"))
      req.body.should contain(%("path":"/dedicated/server/*"))
      req.body.should contain(%("path":"/services/*"))
    end

    it "ajoute `redirection` au body quand fourni" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /\/auth\/credential/,
        status: 200,
        body: %({"validationUrl":"https://eu/","consumerKey":"CK","state":"pendingValidation"}),
      )

      client.auth.request_consumer_key(
        [OvhApi::Endpoints::AccessRule.new(method: "GET", path: "/me")],
        redirection: "https://beryl.example/ok",
      )

      req = transport.requests.find! { |r| r.method == "POST" }
      req.body.should contain(%("redirection":"https://beryl.example/ok"))
    end
  end
end

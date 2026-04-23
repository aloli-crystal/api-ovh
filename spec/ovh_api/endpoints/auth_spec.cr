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

    it "expose days_until_expiration sur le résultat GET currentCredential" do
      transport = FakeTransport.new
      client = build_client(transport)
      # Expiration = dans 27 jours à partir de "maintenant" (approximatif,
      # on teste juste que ça tombe bien entre 26 et 28).
      future = (Time.utc + 27.days).to_rfc3339
      transport.stub(
        "GET",
        /\/auth\/currentCredential/,
        status: 200,
        body: %({
          "credentialId": 12345,
          "applicationId": 67890,
          "creation": "2026-04-01T10:00:00+00:00",
          "expiration": "#{future}",
          "lastUse": null,
          "status": "validated",
          "ovhSupport": false
        }),
      )

      info = client.auth.current_credential
      info.credential_id.should eq(12345_i64)
      info.status.should eq("validated")
      info.last_use.should be_nil
      days = info.days_until_expiration.not_nil!
      days.should be >= 26
      days.should be <= 28
    end

    it "days_until_expiration est nil si la clé est en validité illimitée" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /\/auth\/currentCredential/,
        status: 200,
        body: %({
          "credentialId": 1,
          "applicationId": 1,
          "creation": "2026-04-01T10:00:00+00:00",
          "expiration": null,
          "lastUse": null,
          "status": "validated"
        }),
      )
      info = client.auth.current_credential
      info.days_until_expiration.should be_nil
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

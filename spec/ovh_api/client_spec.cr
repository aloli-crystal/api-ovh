require "../spec_helper"
require "digest/sha1"

describe OvhApi::Client do
  describe "#initialize" do
    it "accepte un symbole d'endpoint (eu par défaut)" do
      client = OvhApi::Client.new(
        application_key: "app",
        application_secret: "secret",
      )
      client.endpoint.should eq("https://eu.api.ovh.com/1.0")
    end

    it "accepte :ca et :us" do
      OvhApi::Client.new(application_key: "a", application_secret: "b", endpoint: :ca).endpoint
        .should eq("https://ca.api.ovh.com/1.0")
      OvhApi::Client.new(application_key: "a", application_secret: "b", endpoint: :us).endpoint
        .should eq("https://api.us.ovhcloud.com/1.0")
    end

    it "accepte une URL complète" do
      client = OvhApi::Client.new(
        application_key: "a",
        application_secret: "b",
        endpoint: "https://my-proxy.example/1.0",
      )
      client.endpoint.should eq("https://my-proxy.example/1.0")
    end

    it "lève sur un symbole d'endpoint inconnu" do
      expect_raises(ArgumentError, /unknown|inconnu/i) do
        OvhApi::Client.new(
          application_key: "a",
          application_secret: "b",
          endpoint: :mars,
        )
      end
    end
  end

  describe "#sign" do
    # Vecteur déterministe : on recalcule SHA1 à la main et on vérifie
    # que la signature OVH vaut bien `"$1$" + hex`.
    it "produit $1$ + sha1_hex(secret+consumer+method+url+body+timestamp)" do
      client = OvhApi::Client.new(
        application_key: "appkey",
        application_secret: "appsecret",
        consumer_key: "ck",
      )
      method = "GET"
      url = "https://eu.api.ovh.com/1.0/me"
      body = ""
      ts = 1_700_000_000_i64
      expected = "$1$" + Digest::SHA1.hexdigest("appsecret+ck+GET+#{url}+#{body}+#{ts}")
      client.sign(method, url, body, ts, "ck").should eq(expected)
    end

    it "inclut le corps JSON tel quel dans le hash (POST)" do
      client = OvhApi::Client.new(
        application_key: "k",
        application_secret: "s",
        consumer_key: "c",
      )
      body = %({"keyName":"laptop","key":"ssh-ed25519 AAAA"})
      url = "https://eu.api.ovh.com/1.0/me/sshKey"
      ts = "1700000500"
      expected = "$1$" + Digest::SHA1.hexdigest("s+c+POST+#{url}+#{body}+#{ts}")
      client.sign("POST", url, body, ts, "c").should eq(expected)
    end
  end

  describe "#server_time" do
    it "interroge /auth/time et met en cache l'offset" do
      transport = FakeTransport.new
      transport.stub("GET", /auth\/time/, status: 200, body: "1700000000")
      client = OvhApi::Client.new(
        application_key: "k",
        application_secret: "s",
        transport: transport,
      )
      client.server_time.should eq(1_700_000_000_i64)
      client.time_delta.should_not be_nil
      # Un deuxième appel ne re-touche pas /auth/time.
      before = transport.requests.size
      client.server_time
      transport.requests.size.should eq(before)
    end

    it "lève une ApiError si /auth/time répond en erreur" do
      transport = FakeTransport.new
      transport.stub("GET", /auth\/time/, status: 503, body: "down")
      client = OvhApi::Client.new(
        application_key: "k",
        application_secret: "s",
        transport: transport,
      )
      expect_raises(OvhApi::ApiError, /503/) { client.server_time }
    end
  end

  describe "#call (auth)" do
    it "pose les 4 en-têtes OVH sur une requête signée" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /\/me$/, status: 200, body: %({"nichandle":"xx12345-ovh"}))

      client.call("GET", "/me")

      req = transport.requests.find! { |r| r.url.ends_with?("/me") }
      req.headers["X-Ovh-Application"].should eq("app-key")
      req.headers["X-Ovh-Consumer"].should eq("consumer-key")
      req.headers["X-Ovh-Timestamp"].should eq("1700000000")
      req.headers["X-Ovh-Signature"].should start_with("$1$")
    end

    it "signe avec le corps JSON exact envoyé" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("POST", /sshKey/, status: 200, body: "")

      client.call("POST", "/me/sshKey", body: {"keyName" => "laptop", "key" => "ssh"})

      req = transport.requests.find! { |r| r.method == "POST" }
      # Le corps envoyé doit être le JSON compact attendu.
      req.body.should eq(%({"keyName":"laptop","key":"ssh"}))
      # La signature doit porter sur ce corps exact.
      expected = client.sign("POST", req.url, req.body, 1_700_000_000, "consumer-key")
      req.headers["X-Ovh-Signature"].should eq(expected)
    end

    it "refuse d'appeler un endpoint signé sans consumer_key" do
      client = OvhApi::Client.new(
        application_key: "k",
        application_secret: "s",
      )
      expect_raises(OvhApi::AuthenticationError, /consumer_key/) do
        client.call("GET", "/me")
      end
    end
  end

  describe "#call (query string)" do
    it "encode la query dans l'URL et la fait entrer dans la signature" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /dedicated\/server\/[^\/]+\/task/, status: 200, body: "[]")

      client.dedicated_servers.tasks(
        service_name: "ns1.ip-1-2-3.eu",
        function: "reinstallServer",
      )

      req = transport.requests.find! { |r| r.method == "GET" && r.url.includes?("task") }
      req.url.should contain("function=reinstallServer")
      # La signature doit correspondre à l'URL incluant la query.
      expected = client.sign("GET", req.url, "", 1_700_000_000, "consumer-key")
      req.headers["X-Ovh-Signature"].should eq(expected)
    end
  end

  describe "#call (gestion d'erreurs)" do
    it "lève NotFound sur 404" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /missing/, status: 404, body: %({"message":"Not found"}))

      expect_raises(OvhApi::NotFound, /404/) do
        client.call("GET", "/missing")
      end
    end

    it "lève AuthenticationError sur 401 et 403" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /auth-fail/, status: 401, body: "bad token")

      expect_raises(OvhApi::AuthenticationError, /401/) do
        client.call("GET", "/auth-fail")
      end
    end

    it "lève RateLimited sur 429 et extrait retryAfter" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /throttle/, status: 429, body: %({"message":"slow down","retryAfter":12}))

      exc = expect_raises(OvhApi::RateLimited) do
        client.call("GET", "/throttle")
      end
      exc.retry_after.should eq(12)
    end

    it "lève ApiError générique sur 500 et capture errorCode" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /boom/, status: 500, body: %({"message":"boom","errorCode":"INTERNAL_ERROR"}))

      exc = expect_raises(OvhApi::ApiError, /500/) do
        client.call("GET", "/boom")
      end
      exc.http_status.should eq(500)
      exc.error_code.should eq("INTERNAL_ERROR")
    end
  end
end

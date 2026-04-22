require "../../spec_helper"

describe OvhApi::Endpoints::Domains do
  describe "#records" do
    it "liste tous les records d'une zone" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /domain\/zone\/aloli\.net\/record/,
        status: 200,
        body: %([42, 43, 44]),
      )

      ids = client.domains.records("aloli.net")
      ids.should eq([42_i64, 43_i64, 44_i64])
    end

    it "filtre par fieldType et subDomain via query string" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /domain\/zone\/aloli\.net\/record.*fieldType=CNAME.*subDomain=loulou/,
        status: 200,
        body: %([100]),
      )

      ids = client.domains.records("aloli.net", field_type: "CNAME", sub_domain: "loulou")
      ids.should eq([100_i64])
    end
  end

  describe "#record" do
    it "renvoie le détail d'un record" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /domain\/zone\/aloli\.net\/record\/42/,
        status: 200,
        body: %({"id":42,"zone":"aloli.net","subDomain":"loulou","fieldType":"CNAME","target":"ns3156789.ip-51-83-6.eu.","ttl":3600}),
      )

      rec = client.domains.record("aloli.net", 42_i64)
      rec.id.should eq(42_i64)
      rec.sub_domain.should eq("loulou")
      rec.field_type.should eq("CNAME")
      rec.target.should eq("ns3156789.ip-51-83-6.eu.")
      rec.ttl.should eq(3600)
      rec.fqdn.should eq("loulou.aloli.net")
    end
  end

  describe "#create_record" do
    it "POSTe fieldType + subDomain + target" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /domain\/zone\/aloli\.net\/record/,
        status: 200,
        body: %({"id":99,"zone":"aloli.net","subDomain":"loulou","fieldType":"CNAME","target":"ns3156789.ip-51-83-6.eu.","ttl":0}),
      )

      rec = client.domains.create_record(
        zone: "aloli.net",
        field_type: "CNAME",
        sub_domain: "loulou",
        target: "ns3156789.ip-51-83-6.eu.",
      )
      rec.id.should eq(99_i64)

      req = transport.requests.find! { |r| r.method == "POST" }
      req.body.should contain(%("fieldType":"CNAME"))
      req.body.should contain(%("subDomain":"loulou"))
      req.body.should contain(%("target":"ns3156789.ip-51-83-6.eu."))
    end

    it "inclut ttl quand fourni" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /domain\/zone\/aloli\.net\/record/,
        status: 200,
        body: %({"id":99,"zone":"aloli.net","subDomain":"loulou","fieldType":"A","target":"1.2.3.4","ttl":60}),
      )

      client.domains.create_record(
        zone: "aloli.net",
        field_type: "A",
        sub_domain: "loulou",
        target: "1.2.3.4",
        ttl: 60,
      )

      req = transport.requests.find! { |r| r.method == "POST" }
      req.body.should contain(%("ttl":60))
    end
  end

  describe "#update_record" do
    it "PUT uniquement les champs fournis" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("PUT", /domain\/zone\/aloli\.net\/record\/42/, status: 200, body: "null")

      client.domains.update_record("aloli.net", 42_i64, target: "autre.exemple.eu.")

      req = transport.requests.find! { |r| r.method == "PUT" }
      req.body.should contain(%("target":"autre.exemple.eu."))
      req.body.should_not contain(%("subDomain"))
    end
  end

  describe "#delete_record" do
    it "DELETE /record/{id}" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("DELETE", /domain\/zone\/aloli\.net\/record\/42/, status: 200, body: "null")

      client.domains.delete_record("aloli.net", 42_i64)
      transport.requests.any? { |r| r.method == "DELETE" }.should be_true
    end
  end

  describe "#refresh" do
    it "POST /domain/zone/{zone}/refresh" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("POST", /domain\/zone\/aloli\.net\/refresh/, status: 200, body: "null")

      client.domains.refresh("aloli.net")
      transport.requests.any? { |r| r.method == "POST" && r.url.includes?("/refresh") }.should be_true
    end
  end

  describe "#ensure_record" do
    it "crée si aucun record n'existe" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /record/, status: 200, body: "[]")
      transport.stub(
        "POST",
        /record/,
        status: 200,
        body: %({"id":1,"zone":"aloli.net","subDomain":"loulou","fieldType":"CNAME","target":"ns.example.","ttl":0}),
      )

      rec = client.domains.ensure_record("aloli.net", "CNAME", "loulou", "ns.example.")
      rec.target.should eq("ns.example.")
      transport.requests.any? { |r| r.method == "POST" }.should be_true
    end

    it "ne fait rien si le record existe déjà avec la bonne cible" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /record\?.*fieldType/, status: 200, body: "[42]")
      transport.stub(
        "GET",
        /record\/42$/,
        status: 200,
        body: %({"id":42,"zone":"aloli.net","subDomain":"loulou","fieldType":"CNAME","target":"ns.example.","ttl":3600}),
      )

      rec = client.domains.ensure_record("aloli.net", "CNAME", "loulou", "ns.example.")
      rec.id.should eq(42_i64)
      # Pas de POST ni de PUT : le record était déjà bon.
      transport.requests.any? { |r| r.method == "POST" || r.method == "PUT" }.should be_false
    end

    it "met à jour si la cible diffère" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /record\?.*fieldType/, status: 200, body: "[42]")
      transport.stub(
        "GET",
        /record\/42$/,
        status: 200,
        body: %({"id":42,"zone":"aloli.net","subDomain":"loulou","fieldType":"CNAME","target":"ancien.example.","ttl":3600}),
      )
      transport.stub("PUT", /record\/42/, status: 200, body: "null")

      client.domains.ensure_record("aloli.net", "CNAME", "loulou", "nouveau.example.")

      put = transport.requests.find! { |r| r.method == "PUT" }
      put.body.should contain(%("target":"nouveau.example."))
    end
  end
end

require "../../spec_helper"

describe OvhApi::Endpoints::Sms do
  describe "#services" do
    it "GET /sms et renvoie la liste des serviceName" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /\/sms$/, status: 200, body: %(["sms-ab1234-1","sms-cd5678-2"]))

      services = client.sms.services

      services.should eq(["sms-ab1234-1", "sms-cd5678-2"])
      req = transport.requests.find!(&.url.ends_with?("/sms"))
      req.method.should eq("GET")
    end
  end

  describe "#service" do
    it "GET /sms/{name} et expose credits_left" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET", /\/sms\/sms-ab1234-1$/,
        status: 200,
        body: %({
          "name": "sms-ab1234-1",
          "creditsLeft": 4216,
          "callBack": null,
          "status": "enable"
        }),
      )

      info = client.sms.service("sms-ab1234-1")

      info.name.should eq("sms-ab1234-1")
      info.credits_left.should eq(4216)
      info.callback_url.should be_nil
      info.status.should eq("enable")
    end

    it "tolère un creditsLeft renvoyé en float par OVH" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET", /\/sms\/sms-ab1234-1$/,
        status: 200,
        body: %({"name": "sms-ab1234-1", "creditsLeft": 42.0, "status": "enable"}),
      )

      client.sms.service("sms-ab1234-1").credits_left.should eq(42)
    end
  end

  describe "#send" do
    it "POST /sms/{name}/jobs avec sender + noStopClause + priority" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST", /\/sms\/sms-ab1234-1\/jobs$/,
        status: 200,
        body: %({
          "ids": [1234567890],
          "totalCreditsRemoved": 1,
          "validReceivers": ["+33612345678"],
          "invalidReceivers": []
        }),
      )

      result = client.sms.send(
        service_name: "sms-ab1234-1",
        receivers: ["+33612345678"],
        message: "Quimeo Quizz - votre code : 123456 (valable 3 min)",
        sender: "QUIMEOSAS",
      )

      result.ids.should eq([1234567890_i64])
      result.total_credits_removed.should eq(1)
      result.valid_receivers.should eq(["+33612345678"])
      result.invalid_receivers.should be_empty
      result.fully_accepted?.should be_true

      req = transport.requests.find!(&.url.ends_with?("/sms/sms-ab1234-1/jobs"))
      req.method.should eq("POST")
      req.body.should contain(%("message":"Quimeo Quizz))
      req.body.should contain(%("receivers":["+33612345678"]))
      req.body.should contain(%("sender":"QUIMEOSAS"))
      req.body.should contain(%("noStopClause":true))
      req.body.should contain(%("priority":"high"))
      # Signature posée (request signée).
      req.headers["X-Ovh-Signature"].should start_with("$1$")
      req.headers["X-Ovh-Application"].should eq("app-key")
      req.headers["X-Ovh-Consumer"].should eq("consumer-key")
    end

    it "expose les invalidReceivers (numéro mal saisi côté allowlist)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST", /\/sms\/sms-ab1234-1\/jobs$/,
        status: 200,
        body: %({
          "ids": [],
          "totalCreditsRemoved": 0,
          "validReceivers": [],
          "invalidReceivers": ["+33612345678"]
        }),
      )

      result = client.sms.send(
        service_name: "sms-ab1234-1",
        receivers: ["+33612345678"],
        message: "x",
        sender: "QUIMEOSAS",
      )

      result.fully_accepted?.should be_false
      result.invalid_receivers.should eq(["+33612345678"])
      result.total_credits_removed.should eq(0)
    end

    it "n'envoie pas le sender s'il n'est pas fourni (numéro court anonyme OVH)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST", /\/sms\/sms-ab1234-1\/jobs$/,
        status: 200,
        body: %({"ids":[1],"totalCreditsRemoved":1,"validReceivers":["+33612345678"],"invalidReceivers":[]}),
      )

      client.sms.send(
        service_name: "sms-ab1234-1",
        receivers: ["+33612345678"],
        message: "x",
      )

      req = transport.requests.find!(&.url.ends_with?("/jobs"))
      req.body.should_not contain("sender")
    end
  end
end

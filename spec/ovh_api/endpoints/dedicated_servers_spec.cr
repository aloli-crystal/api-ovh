require "../../spec_helper"

describe OvhApi::Endpoints::DedicatedServers do
  it "liste les serviceName du compte" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /dedicated\/server$/,
      status: 200,
      body: %(["ns1.ip-1-2-3.eu","ns2.ip-4-5-6.eu"]),
    )

    client.dedicated_servers.list.should eq(["ns1.ip-1-2-3.eu", "ns2.ip-4-5-6.eu"])
  end

  it "récupère les infos d'un serveur" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /dedicated\/server\/ns1/,
      status: 200,
      body: %({"name":"ns1.ip-1-2-3.eu","state":"ok","reverse":"web01.aloli.fr."}),
    )

    info = client.dedicated_servers.info("ns1.ip-1-2-3.eu")
    info["state"].as_s.should eq("ok")
  end

  it "liste les templates d'installation" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /installationTemplate/,
      status: 200,
      body: %(["debian12_64","ubuntu2404-server_64"]),
    )

    client.dedicated_servers.installation_templates.should eq(["debian12_64", "ubuntu2404-server_64"])
  end

  describe "#reinstall" do
    it "POSTe operatingSystem + customizations (hostname + sshKey)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /reinstall/,
        status: 200,
        body: %({"taskId":42,"function":"reinstallServer","status":"init"}),
      )

      task = client.dedicated_servers.reinstall(
        service_name: "ns1.ip-1-2-3.eu",
        template: "debian12_64",
        hostname: "web01.aloli.fr",
        ssh_key_name: "laptop",
      )

      task.id.should eq(42_i64)
      task.function.should eq("reinstallServer")
      task.status.should eq("init")
      task.done?.should be_false

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.body.should contain(%("operatingSystem":"debian12_64"))
      req.body.should contain(%("hostname":"web01.aloli.fr"))
      req.body.should contain(%("sshKey":"laptop"))
    end

    it "n'émet pas de bloc customizations si rien n'est fourni" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /reinstall/,
        status: 200,
        body: %({"taskId":1,"function":"reinstallServer","status":"init"}),
      )

      client.dedicated_servers.reinstall(
        service_name: "ns1.ip-1-2-3.eu",
        template: "debian12_64",
      )

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.body.should_not contain("customizations")
    end
  end

  describe "#tasks" do
    it "liste les taskId" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /task$/, status: 200, body: "[42,43]")

      client.dedicated_servers.tasks(service_name: "ns1.ip-1-2-3.eu")
        .should eq([42_i64, 43_i64])
    end

    it "transmet les filtres function/status en query" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /task/, status: 200, body: "[]")

      client.dedicated_servers.tasks(
        service_name: "ns1.ip-1-2-3.eu",
        function: "reinstallServer",
        status: "doing",
      )

      req = transport.requests.find { |r| r.method == "GET" && r.url.includes?("task") }.not_nil!
      req.url.should contain("function=reinstallServer")
      req.url.should contain("status=doing")
    end
  end

  describe "#task" do
    it "récupère une tâche individuelle et décode ses champs" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /task\/42/,
        status: 200,
        body: %({
          "taskId": 42,
          "function": "reinstallServer",
          "status": "done",
          "comment": "ok",
          "startDate": "2026-04-18T10:00:00+02:00",
          "doneDate": "2026-04-18T10:45:00+02:00",
          "lastUpdate": "2026-04-18T10:45:00+02:00"
        }),
      )

      task = client.dedicated_servers.task(
        service_name: "ns1.ip-1-2-3.eu",
        task_id: 42,
      )
      task.done?.should be_true
      task.success?.should be_true
      task.failed?.should be_false
      task.comment.should eq("ok")
    end
  end

  describe "#boots" do
    it "liste les bootId disponibles pour un serveur" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /dedicated\/server\/ns1\.ip-1-2-3\.eu\/boot$/,
        status: 200,
        body: "[1,2,3,42]",
      )

      client.dedicated_servers.boots("ns1.ip-1-2-3.eu")
        .should eq([1_i64, 2_i64, 3_i64, 42_i64])
    end
  end

  describe "#boot" do
    it "décode le détail d'un boot (struct Boot)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /dedicated\/server\/ns1\.ip-1-2-3\.eu\/boot\/42/,
        status: 200,
        body: %({
          "bootId": 42,
          "bootType": "rescue",
          "kernel": "rescue64-pro",
          "description": "Rescue 64 bits",
          "supportsUEFI": "yes"
        }),
      )

      boot = client.dedicated_servers.boot("ns1.ip-1-2-3.eu", 42_i64)
      boot.id.should eq(42_i64)
      boot.boot_type.should eq("rescue")
      boot.kernel.should eq("rescue64-pro")
      boot.description.should eq("Rescue 64 bits")
      boot.supports_uefi.should eq("yes")
      boot.uefi_compatible?.should be_true
    end

    it "considère un boot sans supportsUEFI comme compatible" do
      boot = OvhApi::Endpoints::Boot.new(id: 1, boot_type: "harddisk")
      boot.uefi_compatible?.should be_true
    end

    it "rejette un boot avec supportsUEFI=no" do
      boot = OvhApi::Endpoints::Boot.new(
        id: 1,
        boot_type: "rescue",
        supports_uefi: "no",
      )
      boot.uefi_compatible?.should be_false
    end
  end

  describe "#set_boot" do
    it "PUT /dedicated/server/{serviceName} avec bootId en corps" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "PUT",
        /dedicated\/server\/ns1\.ip-1-2-3\.eu$/,
        status: 200,
        body: "",
      )

      client.dedicated_servers.set_boot("ns1.ip-1-2-3.eu", 42_i64)

      req = transport.requests.find { |r| r.method == "PUT" }.not_nil!
      req.url.should end_with("/dedicated/server/ns1.ip-1-2-3.eu")
      req.body.should contain(%("bootId":42))
    end
  end

  describe "#set_netboot_option" do
    it "POST /netbootOption avec option et value" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /netbootOption/,
        status: 200,
        body: "",
      )

      client.dedicated_servers.set_netboot_option(
        service_name: "ns1.ip-1-2-3.eu",
        option: "rescueSshKey",
        value: "laptop",
      )

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.url.should end_with("/dedicated/server/ns1.ip-1-2-3.eu/netbootOption")
      req.body.should contain(%("option":"rescueSshKey"))
      req.body.should contain(%("value":"laptop"))
    end
  end

  describe "#reboot" do
    it "POST /reboot et décode la Task" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /reboot/,
        status: 200,
        body: %({"taskId":99,"function":"hardReboot","status":"init"}),
      )

      task = client.dedicated_servers.reboot("ns1.ip-1-2-3.eu")

      task.id.should eq(99_i64)
      task.function.should eq("hardReboot")
      task.status.should eq("init")
      task.done?.should be_false

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.url.should end_with("/dedicated/server/ns1.ip-1-2-3.eu/reboot")
    end
  end

  describe "Task#done?" do
    it "true pour done, cancelled, ovhError, customerError" do
      base = {"taskId" => 1_i64, "function" => "x"}
      ["done", "cancelled", "ovhError", "customerError"].each do |status|
        task = OvhApi::Endpoints::Task.new(id: 1, function: "x", status: status)
        task.done?.should be_true
      end
    end

    it "false pour todo, doing, init" do
      ["todo", "doing", "init"].each do |status|
        task = OvhApi::Endpoints::Task.new(id: 1, function: "x", status: status)
        task.done?.should be_false
      end
    end
  end
end

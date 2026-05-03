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

  it "met à jour le displayName via GET serviceInfos puis PUT /services/{id}" do
    # Flux à deux étapes : le displayName ne vit plus sur
    # /dedicated/server/{X} (OVH a retiré ce champ, HTTP 400), mais sur
    # /services/{serviceId}. On découvre le serviceId via serviceInfos.
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /dedicated\/server\/ns1\.ip-1-2-3\.eu\/serviceInfos/,
      status: 200,
      body: %({"serviceId":123456789,"status":"ok"}),
    )
    transport.stub("PUT", /\/services\/123456789/, status: 200, body: "null")

    client.dedicated_servers.update("ns1.ip-1-2-3.eu", display_name: "loulou.aloli.net")

    put = transport.requests.find! { |r| r.method == "PUT" }
    put.url.should contain("/services/123456789")
    put.body.should contain(%("displayName":"loulou.aloli.net"))
  end

  it "n'appelle pas l'API si aucun champ n'est fourni à update" do
    transport = FakeTransport.new
    client = build_client(transport)

    client.dedicated_servers.update("ns1.ip-1-2-3.eu")

    transport.requests.should be_empty
  end

  it "service_id_for résout serviceName → serviceId via serviceInfos" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /dedicated\/server\/ns1\.ip-1-2-3\.eu\/serviceInfos/,
      status: 200,
      body: %({"serviceId":42,"status":"ok"}),
    )
    client.dedicated_servers.service_id_for("ns1.ip-1-2-3.eu").should eq(42_i64)
  end

  it "liste les IPs du serveur" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /dedicated\/server\/ns1\.ip-1-2-3\.eu\/ips/,
      status: 200,
      body: %(["51.83.6.123/32","2001:41d0:2:6e01::/64"]),
    )

    ips = client.dedicated_servers.ips("ns1.ip-1-2-3.eu")
    ips.should eq(["51.83.6.123/32", "2001:41d0:2:6e01::/64"])
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

      req = transport.requests.find! { |r| r.method == "POST" }
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

      req = transport.requests.find! { |r| r.method == "POST" }
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

      req = transport.requests.find! { |r| r.method == "GET" && r.url.includes?("task") }
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

    it "linux_rescue? vrai pour un kernel rescue*" do
      OvhApi::Endpoints::Boot.new(id: 1, boot_type: "rescue", kernel: "rescue12-customer")
        .linux_rescue?.should be_true
      OvhApi::Endpoints::Boot.new(id: 1, boot_type: "rescue", kernel: "rescue64-pro")
        .linux_rescue?.should be_true
    end

    it "linux_rescue? faux pour ipxe-shell et autres" do
      OvhApi::Endpoints::Boot.new(id: 1, boot_type: "rescue", kernel: "ipxe-shell")
        .linux_rescue?.should be_false
      OvhApi::Endpoints::Boot.new(id: 1, boot_type: "rescue", kernel: nil)
        .linux_rescue?.should be_false
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

      req = transport.requests.find! { |r| r.method == "PUT" }
      req.url.should end_with("/dedicated/server/ns1.ip-1-2-3.eu")
      req.body.should contain(%("bootId":42))
    end

    it "PUT avec rescue_ssh_key inclut rescueSshKey dans le corps" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "PUT",
        /dedicated\/server\/ns1\.ip-1-2-3\.eu$/,
        status: 200,
        body: "",
      )

      client.dedicated_servers.set_boot(
        "ns1.ip-1-2-3.eu",
        42_i64,
        rescue_ssh_key: "laptop",
      )

      req = transport.requests.find! { |r| r.method == "PUT" }
      req.body.should contain(%("bootId":42))
      req.body.should contain(%("rescueSshKey":"laptop"))
    end

    it "n'émet pas rescueSshKey quand nil" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "PUT",
        /dedicated\/server\/ns1\.ip-1-2-3\.eu$/,
        status: 200,
        body: "",
      )

      client.dedicated_servers.set_boot("ns1.ip-1-2-3.eu", 42_i64)

      req = transport.requests.find! { |r| r.method == "PUT" }
      req.body.should_not contain("rescueSshKey")
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

      req = transport.requests.find! { |r| r.method == "POST" }
      req.url.should end_with("/dedicated/server/ns1.ip-1-2-3.eu/reboot")
    end
  end

  describe "#prepare_rescue" do
    it "orchestre boots → boot → set_boot (avec rescueSshKey) → reboot" do
      transport = FakeTransport.new
      client = build_client(transport)

      # Liste de bootId : 1 = harddisk, 42 = rescue.
      transport.stub(
        "GET",
        /\/boot$/,
        status: 200,
        body: "[1,42]",
      )
      transport.stub(
        "GET",
        /\/boot\/1$/,
        status: 200,
        body: %({"bootId":1,"bootType":"harddisk","supportsUEFI":"yes"}),
      )
      transport.stub(
        "GET",
        /\/boot\/42$/,
        status: 200,
        body: %({"bootId":42,"bootType":"rescue","kernel":"rescue64-pro","supportsUEFI":"yes"}),
      )
      # Lookup du contenu de la clé (depuis 0.2.2, OVH attend la clé brute
      # pas son nom pour rescueSshKey — la doc dit « name » mais l'API
      # rejette avec 400 « SSH key is not valid »).
      transport.stub(
        "GET",
        /\/me\/sshKey\/laptop$/,
        status: 200,
        body: %({"keyName":"laptop","key":"ssh-ed25519 AAAA... me@host","default":false}),
      )
      transport.stub(
        "PUT",
        /dedicated\/server\/ns1\.ip-1-2-3\.eu$/,
        status: 200,
        body: "",
      )
      transport.stub(
        "POST",
        /reboot/,
        status: 200,
        body: %({"taskId":500,"function":"hardReboot","status":"init"}),
      )

      task = client.dedicated_servers.prepare_rescue(
        service_name: "ns1.ip-1-2-3.eu",
        ssh_key_name: "laptop",
      )

      task.id.should eq(500_i64)
      task.function.should eq("hardReboot")

      # Séquence attendue depuis 0.2.2 : lookup de la clé pour récupérer
      # son contenu, puis PUT combiné (bootId + rescueSshKey = contenu
      # brut), puis reboot.
      sequence = transport.requests
        .reject { |r| r.url.includes?("/auth/time") }
        .map { |r| "#{r.method} #{r.url.sub(/^.*\/1\.0/, "")}" }

      sequence.should eq([
        "GET /dedicated/server/ns1.ip-1-2-3.eu/boot",
        "GET /dedicated/server/ns1.ip-1-2-3.eu/boot/1",
        "GET /dedicated/server/ns1.ip-1-2-3.eu/boot/42",
        "GET /me/sshKey/laptop",
        "PUT /dedicated/server/ns1.ip-1-2-3.eu",
        "POST /dedicated/server/ns1.ip-1-2-3.eu/reboot",
      ])

      # Le PUT combine bootId=42 et rescueSshKey = **contenu** de la clé.
      put = transport.requests.find! { |r| r.method == "PUT" }
      put.body.should contain(%("bootId":42))
      put.body.should contain(%("rescueSshKey":"ssh-ed25519 AAAA... me@host"))
    end

    it "écarte le rescue ipxe-shell au profit du rescue Linux" do
      transport = FakeTransport.new
      client = build_client(transport)

      # Cas réel OVH : deux boots rescue, un ipxe-shell (non exploitable)
      # et un rescue12-customer (Debian). On doit prendre le second.
      transport.stub("GET", /\/boot$/, status: 200, body: "[203323,230242]")
      transport.stub(
        "GET",
        /\/boot\/203323$/,
        status: 200,
        body: %({"bootId":203323,"bootType":"rescue","kernel":"ipxe-shell","description":"iPXE shell"}),
      )
      transport.stub(
        "GET",
        /\/boot\/230242$/,
        status: 200,
        body: %({"bootId":230242,"bootType":"rescue","kernel":"rescue12-customer","description":"Customer rescue (Debian-12)"}),
      )
      transport.stub(
        "GET",
        /\/me\/sshKey\/laptop$/,
        status: 200,
        body: %({"keyName":"laptop","key":"ssh-ed25519 AAAA...","default":false}),
      )
      transport.stub("PUT", /dedicated\/server\/ns1\.ip-1-2-3\.eu$/, status: 200, body: "")
      transport.stub(
        "POST",
        /reboot/,
        status: 200,
        body: %({"taskId":1,"function":"hardReboot","status":"init"}),
      )

      client.dedicated_servers.prepare_rescue(
        service_name: "ns1.ip-1-2-3.eu",
        ssh_key_name: "laptop",
      )

      put = transport.requests.find! { |r| r.method == "PUT" }
      put.body.should contain(%("bootId":230242))
      put.body.should_not contain("203323")
    end

    it "lève si aucun boot rescue compatible UEFI n'existe" do
      transport = FakeTransport.new
      client = build_client(transport)

      transport.stub("GET", /\/boot$/, status: 200, body: "[1,2]")
      transport.stub(
        "GET",
        /\/boot\/1$/,
        status: 200,
        body: %({"bootId":1,"bootType":"harddisk","supportsUEFI":"yes"}),
      )
      transport.stub(
        "GET",
        /\/boot\/2$/,
        status: 200,
        body: %({"bootId":2,"bootType":"rescue","supportsUEFI":"no"}),
      )

      expect_raises(OvhApi::Error, /Aucun bootId de type 'rescue'/) do
        client.dedicated_servers.prepare_rescue(
          service_name: "ns1.ip-1-2-3.eu",
          ssh_key_name: "laptop",
        )
      end
    end
  end

  describe "#boot_from_disk" do
    it "arme le bootId harddisk puis reboot (orchestration inverse de prepare_rescue)" do
      transport = FakeTransport.new
      client = build_client(transport)

      transport.stub("GET", /\/boot$/, status: 200, body: "[1,42]")
      transport.stub(
        "GET",
        /\/boot\/1$/,
        status: 200,
        body: %({"bootId":1,"bootType":"harddisk","supportsUEFI":"yes"}),
      )
      transport.stub(
        "GET",
        /\/boot\/42$/,
        status: 200,
        body: %({"bootId":42,"bootType":"rescue","kernel":"rescue64-pro"}),
      )
      transport.stub("PUT", /dedicated\/server\/ns1\.ip-1-2-3\.eu$/, status: 200, body: "")
      transport.stub(
        "POST",
        /reboot/,
        status: 200,
        body: %({"taskId":501,"function":"hardReboot","status":"init"}),
      )

      task = client.dedicated_servers.boot_from_disk("ns1.ip-1-2-3.eu")
      task.id.should eq(501_i64)

      put = transport.requests.find! { |r| r.method == "PUT" }
      put.body.should contain(%("bootId":1))
    end

    it "lève si aucun bootId harddisk n'existe" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /\/boot$/, status: 200, body: "[42]")
      transport.stub(
        "GET",
        /\/boot\/42$/,
        status: 200,
        body: %({"bootId":42,"bootType":"rescue","kernel":"rescue64-pro"}),
      )
      expect_raises(OvhApi::Error, /harddisk/) do
        client.dedicated_servers.boot_from_disk("ns1.ip-1-2-3.eu")
      end
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

  describe "#wait_for_task" do
    it "polle jusqu'à done? puis retourne la Task finale" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub_sequence(
        "GET",
        /task\/42$/,
        [
          {200, %({"taskId":42,"function":"reinstallServer","status":"todo"})},
          {200, %({"taskId":42,"function":"reinstallServer","status":"doing"})},
          {200, %({"taskId":42,"function":"reinstallServer","status":"done","doneDate":"2026-05-03T10:00:00+02:00"})},
        ]
      )

      final = client.dedicated_servers.wait_for_task(
        service_name: "ns1.ip-1-2-3.eu",
        task_id: 42,
        interval: 0.seconds,
        timeout: 30.seconds,
      )

      final.success?.should be_true
      final.status.should eq("done")
      transport.requests.count { |r| r.url.includes?("/task/42") }.should eq(3)
    end

    it "lève TaskTimeout si la tâche n'atteint pas l'état terminal" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /task\/99$/,
        status: 200,
        body: %({"taskId":99,"function":"hardReboot","status":"doing"}),
      )

      exc = expect_raises(OvhApi::TaskTimeout, /99/) do
        client.dedicated_servers.wait_for_task(
          service_name: "ns1.ip-1-2-3.eu",
          task_id: 99,
          interval: 0.seconds,
          timeout: 0.seconds,
        )
      end

      exc.last_task.id.should eq(99)
      exc.last_task.status.should eq("doing")
    end

    it "yield la Task à chaque tour pour permettre de logger" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub_sequence(
        "GET",
        /task\/7$/,
        [
          {200, %({"taskId":7,"function":"hardReboot","status":"doing"})},
          {200, %({"taskId":7,"function":"hardReboot","status":"done"})},
        ]
      )

      seen = [] of String
      client.dedicated_servers.wait_for_task(
        service_name: "ns1.ip-1-2-3.eu",
        task_id: 7,
        interval: 0.seconds,
      ) { |t| seen << t.status }

      seen.should eq(["doing", "done"])
    end

    it "remonte un échec OVH (failed?) sans lever, à charge de l'appelant" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /task\/13$/,
        status: 200,
        body: %({"taskId":13,"function":"reinstallServer","status":"customerError","comment":"bad SSH key"}),
      )

      final = client.dedicated_servers.wait_for_task(
        service_name: "ns1.ip-1-2-3.eu",
        task_id: 13,
        interval: 0.seconds,
      )

      final.done?.should be_true
      final.failed?.should be_true
      final.comment.should eq("bad SSH key")
    end
  end
end

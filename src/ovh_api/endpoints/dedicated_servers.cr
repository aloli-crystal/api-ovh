require "json"

module OvhApi
  module Endpoints
    # Endpoints `/dedicated/server` et `/dedicated/installationTemplate`.
    #
    # Les serveurs sont identifiés par leur `serviceName` (ex.
    # `ns1234.ip-1-2-3.eu`). L'installation est déclenchée par un POST
    # qui renvoie un `Task` dont on suit l'avancement via
    # `/dedicated/server/{serviceName}/task/{taskId}`.
    class DedicatedServers
      def initialize(@client : OvhApi::Client)
      end

      # Liste les `serviceName` des serveurs dédiés du compte.
      #
      # `GET /dedicated/server`.
      def list : Array(String)
        result = @client.call("GET", "/dedicated/server")
        result.try(&.as_a.map(&.as_s)) || [] of String
      end

      # Détail d'un serveur (facturation, reverse, état, rack).
      #
      # `GET /dedicated/server/{serviceName}`.
      def info(service_name : String) : JSON::Any
        @client.call("GET", "/dedicated/server/#{service_name}").not_nil!
      end

      # Liste les templates d'installation disponibles (OS standards
      # OVH : Debian, Ubuntu, Rocky, FreeBSD si proposé par la gamme).
      #
      # `GET /dedicated/installationTemplate` → liste de slugs comme
      # `"debian12_64"`, `"ubuntu2404-server_64"`, `"freebsd14.1-zfs_64"`.
      #
      # Retourne des `String` (identifiants) ; pour le détail d'un
      # template, appeler `installation_template/{id}` via `#call`
      # directement.
      def installation_templates : Array(String)
        result = @client.call("GET", "/dedicated/installationTemplate")
        result.try(&.as_a.map(&.as_s)) || [] of String
      end

      # Détail d'un template d'installation.
      #
      # `GET /dedicated/installationTemplate/{templateName}`.
      def installation_template(template_name : String) : JSON::Any
        @client.call("GET", "/dedicated/installationTemplate/#{template_name}").not_nil!
      end

      # Déclenche une réinstallation du serveur.
      #
      # Utilise l'endpoint *moderne* `POST /dedicated/server/{serviceName}/reinstall`
      # (schéma d'API 2024+). Les paramètres OVH récents :
      #
      # * `operatingSystem`  : slug du template (obligatoire).
      # * `customizations`   : bloc optionnel (hostname, sshKey, postInstallScript…).
      # * `storage`          : partitionnement (laisse OVH décider si nil).
      #
      # Retourne un `Task` dont l'`id` sert à interroger l'avancement.
      def reinstall(
        service_name : String,
        template : String,
        hostname : String? = nil,
        ssh_key_name : String? = nil,
        extra : Hash(String, String)? = nil,
      ) : Task
        # Construction du corps JSON à la main : on veut un objet
        # imbriqué (`customizations`) mais la stdlib Crystal n'offre
        # pas de type Hash générique « hétérogène » facile à
        # sérialiser sans friction. `JSON.build` règle le problème en
        # trois lignes et garantit un encodage exact (important : la
        # signature OVH porte sur ce même texte).
        body = JSON.build do |json|
          json.object do
            json.field "operatingSystem", template
            if hostname || ssh_key_name
              json.field "customizations" do
                json.object do
                  json.field "hostname", hostname if hostname
                  json.field "sshKey", ssh_key_name if ssh_key_name
                end
              end
            end
            extra.try &.each { |k, v| json.field k, v }
          end
        end

        result = @client.call(
          "POST",
          "/dedicated/server/#{service_name}/reinstall",
          body: body,
        )
        Task.from_any(result.not_nil!)
      end

      # Liste les identifiants de tâche associés à un serveur.
      #
      # `GET /dedicated/server/{serviceName}/task`.
      # Un filtre `function` (ex. `"reinstallServer"`) et/ou `status`
      # (`"todo"`, `"doing"`, `"done"`, `"ovhError"`, `"customerError"`,
      # `"cancelled"`) peuvent être passés en query.
      def tasks(
        service_name : String,
        function : String? = nil,
        status : String? = nil,
      ) : Array(Int64)
        query = Hash(String, String).new
        query["function"] = function if function
        query["status"] = status if status

        result = @client.call(
          "GET",
          "/dedicated/server/#{service_name}/task",
          query: query.empty? ? nil : query,
        )
        result.try(&.as_a.map(&.as_i64)) || [] of Int64
      end

      # Détail d'une tâche.
      #
      # `GET /dedicated/server/{serviceName}/task/{taskId}`.
      def task(service_name : String, task_id : Int64 | Int32) : Task
        result = @client.call(
          "GET",
          "/dedicated/server/#{service_name}/task/#{task_id}",
        )
        Task.from_any(result.not_nil!)
      end
    end

    # Représente une tâche OVH (install, reboot, diagnostic…).
    #
    # Les états possibles côté OVH :
    #
    # * `init`              — créée, pas encore traitée.
    # * `todo`              — en file.
    # * `doing`             — en cours.
    # * `done`              — succès.
    # * `ovhError`          — échec côté OVH.
    # * `customerError`     — échec dû à la configuration client.
    # * `cancelled`         — annulée.
    struct Task
      getter id : Int64
      getter function : String
      getter status : String
      getter comment : String?
      getter start_date : String?
      getter done_date : String?
      getter last_update : String?

      def initialize(
        @id : Int64,
        @function : String,
        @status : String,
        @comment : String? = nil,
        @start_date : String? = nil,
        @done_date : String? = nil,
        @last_update : String? = nil,
      )
      end

      def self.from_any(payload : JSON::Any) : Task
        new(
          id: payload["taskId"].as_i64,
          function: payload["function"].as_s,
          status: payload["status"].as_s,
          comment: payload["comment"]?.try(&.as_s?),
          start_date: payload["startDate"]?.try(&.as_s?),
          done_date: payload["doneDate"]?.try(&.as_s?),
          last_update: payload["lastUpdate"]?.try(&.as_s?),
        )
      end

      # La tâche est-elle dans un état terminal ?
      # ("done", "cancelled", "ovhError", "customerError").
      def done? : Bool
        status == "done" || failed? || status == "cancelled"
      end

      # La tâche s'est-elle soldée par un échec OVH ou client ?
      def failed? : Bool
        status == "ovhError" || status == "customerError"
      end

      # La tâche est-elle terminée avec succès ?
      def success? : Bool
        status == "done"
      end
    end
  end
end

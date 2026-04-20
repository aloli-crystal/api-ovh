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

      # Liste les `bootId` disponibles pour un serveur.
      #
      # `GET /dedicated/server/{serviceName}/boot` → tableau d'entiers.
      # Chaque `bootId` pointe vers un profil de netboot (harddisk,
      # rescue64-pro, ipxeCustomerScript, etc.), dont le détail est lu
      # via `#boot(service_name, boot_id)`.
      def boots(service_name : String) : Array(Int64)
        result = @client.call("GET", "/dedicated/server/#{service_name}/boot")
        result.try(&.as_a.map(&.as_i64)) || [] of Int64
      end

      # Détail d'un bootId (type, kernel, description, supportsUEFI).
      #
      # `GET /dedicated/server/{serviceName}/boot/{bootId}`.
      def boot(service_name : String, boot_id : Int64) : Boot
        result = @client.call(
          "GET",
          "/dedicated/server/#{service_name}/boot/#{boot_id}",
        )
        Boot.from_any(result.not_nil!)
      end

      # Change le netboot courant du serveur et configure optionnellement
      # les options rescue (clé SSH, email de notification).
      #
      # `PUT /dedicated/server/{serviceName}` avec body JSON contenant
      # `bootId` et, si fournis, `rescueSshKey` et/ou `rescueMail`.
      # OVH répond avec un corps vide en cas de succès.
      #
      # `rescue_ssh_key` est le *nom* d'une clé SSH déclarée dans
      # `/me/sshKey` (voir `client.ssh_keys.list`). Elle sera injectée
      # dans `/root/.ssh/authorized_keys` au démarrage du rescue.
      def set_boot(
        service_name : String,
        boot_id : Int64,
        rescue_ssh_key : String? = nil,
        rescue_mail : String? = nil,
      ) : Nil
        body = JSON.build do |json|
          json.object do
            json.field "bootId", boot_id
            json.field "rescueSshKey", rescue_ssh_key if rescue_ssh_key
            json.field "rescueMail", rescue_mail if rescue_mail
          end
        end

        @client.call(
          "PUT",
          "/dedicated/server/#{service_name}",
          body: body,
        )
        nil
      end

      # Déclenche un redémarrage matériel du serveur.
      #
      # `POST /dedicated/server/{serviceName}/reboot` → retourne une
      # `Task` (function `"hardReboot"` côté OVH). Le reboot applique le
      # netboot courant ; configurer `set_boot` (avec `rescue_ssh_key`
      # si nécessaire) *avant* d'appeler cette méthode.
      def reboot(service_name : String) : Task
        result = @client.call(
          "POST",
          "/dedicated/server/#{service_name}/reboot",
        )
        Task.from_any(result.not_nil!)
      end

      # Orchestration complète « bascule en rescue + clé SSH + reboot ».
      #
      # Enchaîne :
      #
      # . `boots` puis `boot(id)` pour trouver le `bootId` rescue adapté.
      #   Critère : `bootType == "rescue"` et `supportsUEFI` vaut `"yes"`,
      #   `"both"`, `"only"` ou est absent. S'il y a plusieurs candidats,
      #   on retient le premier (les gammes récentes n'en exposent qu'un).
      # . `ssh_keys.get(ssh_key_name)` pour résoudre le **contenu** de la
      #   clé publique. La doc OVH parle d'un « nom » pour `rescueSshKey`
      #   mais l'API attend en réalité la *clé brute* (observé en v0.2.1
      #   sur un Kimsufi KS-B : `{"message":"SSH key is not valid"}` en
      #   retour quand on passait le nom).
      # . `set_boot(service_name, rescue_id, rescue_ssh_key: <contenu>)`
      #   pour armer le netboot rescue et déclarer la clé à injecter en
      #   une seule requête `PUT /dedicated/server/{serviceName}`.
      # . `reboot(service_name)` pour appliquer.
      #
      # `ssh_key_name` doit déjà exister dans `/me/sshKey` (à créer via
      # `client.ssh_keys.create` si besoin).
      #
      # Retourne la `Task` du reboot ; à poller avec `#task`.
      def prepare_rescue(service_name : String, ssh_key_name : String) : Task
        rescue_id = find_rescue_boot_id(service_name)
        ssh_key_content = @client.ssh_keys.get(ssh_key_name).key
        set_boot(service_name, rescue_id, rescue_ssh_key: ssh_key_content)
        reboot(service_name)
      end

      # Cherche un `bootId` de type rescue compatible UEFI sur le serveur.
      # Lève une `OvhApi::Error` si aucun candidat n'est trouvé.
      private def find_rescue_boot_id(service_name : String) : Int64
        candidates = boots(service_name).compact_map do |id|
          detail = boot(service_name, id)
          if detail.boot_type == "rescue" && detail.uefi_compatible?
            detail
          else
            nil
          end
        end

        if candidates.empty?
          raise Error.new(
            "Aucun bootId de type 'rescue' compatible UEFI trouvé pour " \
            "#{service_name}. Vérifier /dedicated/server/#{service_name}/boot."
          )
        end
        candidates.first.id
      end
    end

    # Profil de netboot exposé par OVH pour un serveur donné.
    #
    # Un `Boot` décrit comment démarrer le serveur : depuis le disque
    # (`harddisk`), en mode rescue (`rescue` → kernel `rescue64-pro`,
    # fournit un environnement diskless pour diagnostic), via un script
    # iPXE client (`ipxeCustomerScript`), par PXE réseau (`network`) ou
    # simple gestion d'alim (`power`).
    #
    # Les `bootId` varient *selon la gamme et le serveur* : un Advance-1
    # et un Scale-3 n'auront pas les mêmes identifiants. Il faut donc les
    # résoudre dynamiquement via `client.dedicated_servers.boots(...)`.
    struct Boot
      getter id : Int64
      getter boot_type : String
      getter kernel : String?
      getter description : String?
      getter supports_uefi : String?

      def initialize(
        @id : Int64,
        @boot_type : String,
        @kernel : String? = nil,
        @description : String? = nil,
        @supports_uefi : String? = nil,
      )
      end

      def self.from_any(payload : JSON::Any) : Boot
        new(
          id: payload["bootId"].as_i64,
          boot_type: payload["bootType"].as_s,
          kernel: payload["kernel"]?.try(&.as_s?),
          description: payload["description"]?.try(&.as_s?),
          supports_uefi: payload["supportsUEFI"]?.try(&.as_s?),
        )
      end

      # Le boot est-il compatible avec un démarrage UEFI ?
      #
      # OVH expose `supportsUEFI` avec les valeurs documentées `"yes"`,
      # `"no"`, `"both"`, `"only"`. Certains profils (power, anciens
      # netboots) ne renseignent pas le champ : on considère alors que
      # la question ne se pose pas et on répond `true` (sinon on
      # exclurait à tort les serveurs sans UEFI).
      def uefi_compatible? : Bool
        case @supports_uefi
        when nil, "yes", "both", "only"
          true
        else
          false
        end
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

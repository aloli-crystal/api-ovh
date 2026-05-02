module OvhApi
  module Endpoints
    # Endpoint `/sms` : envoi de SMS à la demande via un service SMS
    # OVH (pack pré-payé). Couvre :
    #
    # * `send` — envoi d'un SMS court (1 segment) à un ou plusieurs
    #   destinataires E.164. Renvoie le nombre de crédits consommés
    #   et la liste des destinataires acceptés / refusés.
    # * `service` — métadonnées d'un service SMS (crédit restant,
    #   marketing/transactional, etc.).
    # * `services` — liste des `serviceName` accessibles à la consumer
    #   key courante. Pratique pour valider la config au boot.
    #
    # Toutes les méthodes utilisent `Client#call` (signature HMAC + retry
    # si l'horloge locale est en dérive). Les erreurs OVH (4xx/5xx)
    # remontent en `OvhApi::ApiError`.
    #
    # Pré-requis côté OVH :
    #
    # * Un pack SMS commandé sur https://www.ovhtelecom.fr/sms/.
    # * Une consumer key avec les scopes
    #   `GET /sms/*` + `POST /sms/*/jobs` (URL pratique pour générer
    #   tout d'un coup : eu.api.ovh.com/createToken/?GET=/sms/*&POST=/sms/*/jobs).
    # * Un sender alphanumérique (3-11 caractères, validé par OVH).
    class Sms
      def initialize(@client : Client)
      end

      # Liste les `serviceName` SMS accessibles à la consumer key
      # courante. Utile au boot pour valider la config :
      #
      # ```
      # services = client.sms.services
      # raise "Service SMS introuvable" unless services.includes?(ENV["OVH_SMS_SERVICE"])
      # ```
      def services : Array(String)
        response = @client.call("GET", "/sms").not_nil!
        response.as_a.map(&.as_s)
      end

      # Métadonnées du service SMS (crédit restant, type marketing /
      # transactional, callback URL, etc.).
      def service(service_name : String) : ServiceInfo
        response = @client.call("GET", "/sms/#{service_name}").not_nil!
        ServiceInfo.new(
          name: response["name"].as_s,
          credits_left: response["creditsLeft"]?.try(&.as_f?).try(&.to_i) ||
                        response["creditsLeft"]?.try(&.as_i?) || 0,
          callback_url: response["callBack"]?.try(&.as_s?),
          status: response["status"]?.try(&.as_s?) || "unknown",
        )
      end

      # Envoi synchrone d'un SMS. Renvoie un `JobResult` qui contient
      # le nombre de crédits consommés et les destinataires acceptés
      # par OVH (un numéro mal formé ou en blacklist apparaît dans
      # `invalid_receivers` au lieu de `valid_receivers`).
      #
      # Paramètres :
      #
      # * `service_name`     — `sms-xxxxxx-1` (visible sur le manager OVH).
      # * `receivers`        — liste de numéros E.164 (`+33612345678`).
      # * `message`          — corps du SMS. > 160 caractères = SMS multi-
      #   segments (chaque segment compte 1 crédit).
      # * `sender`           — nom expéditeur (3-11 alphanumériques, validé
      #   par OVH au préalable). Si non fourni, OVH utilise un numéro
      #   court anonyme.
      # * `no_stop_clause`   — true pour les SMS non-commerciaux (gagne
      #   les caractères de « STOP au xxxxx »). Défaut true (l'usage 2FA
      #   typique n'est pas commercial).
      # * `priority`         — `"high"` | `"medium"` | `"low"` | `"veryLow"`.
      #   Défaut `"high"` (cas d'usage 2FA / OTP — le code doit arriver vite).
      # * `validity_period`  — durée maximale d'attente en minutes avant
      #   abandon par l'opérateur. Défaut 1440 (24 h, valeur OVH par défaut).
      def send(
        service_name : String,
        receivers : Array(String),
        message : String,
        sender : String? = nil,
        no_stop_clause : Bool = true,
        priority : String = "high",
        validity_period : Int32 = 1440,
      ) : JobResult
        body = {} of String => JSON::Any
        body["message"] = JSON::Any.new(message)
        body["receivers"] = JSON::Any.new(receivers.map { |r| JSON::Any.new(r) })
        body["sender"] = JSON::Any.new(sender) if sender
        body["noStopClause"] = JSON::Any.new(no_stop_clause)
        body["priority"] = JSON::Any.new(priority)
        body["validityPeriod"] = JSON::Any.new(validity_period.to_i64)

        response = @client.call(
          "POST", "/sms/#{service_name}/jobs",
          body: body,
        ).not_nil!

        JobResult.new(
          ids: response["ids"]?.try(&.as_a?).try(&.map(&.as_i64)) || [] of Int64,
          total_credits_removed: response["totalCreditsRemoved"]?.try(&.as_f?).try(&.to_i) ||
                                 response["totalCreditsRemoved"]?.try(&.as_i?) || 0,
          valid_receivers: response["validReceivers"]?.try(&.as_a?).try(&.map(&.as_s)) || [] of String,
          invalid_receivers: response["invalidReceivers"]?.try(&.as_a?).try(&.map(&.as_s)) || [] of String,
        )
      end
    end

    # Métadonnées d'un service SMS OVH. `credits_left` est exprimé en
    # crédits SMS (1 SMS court = 1 crédit, 1 SMS long = 2-3 crédits).
    record ServiceInfo,
      name : String,
      credits_left : Int32,
      callback_url : String?,
      status : String

    # Résultat d'un envoi SMS. `valid_receivers` + `invalid_receivers`
    # = `receivers` envoyé en entrée. Si `invalid_receivers` n'est pas
    # vide, alerter l'opérateur (numéro mal saisi côté allowlist).
    record JobResult,
      ids : Array(Int64),
      total_credits_removed : Int32,
      valid_receivers : Array(String),
      invalid_receivers : Array(String) do
      def fully_accepted? : Bool
        @invalid_receivers.empty?
      end
    end
  end
end

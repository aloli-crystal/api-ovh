module OvhApi
  module Endpoints
    # Endpoint `/auth` : flux de création d'une consumer key OVH.
    #
    # La route `POST /auth/credential` est spéciale : elle ne nécessite
    # PAS de consumer key (c'est précisément ce qu'on demande), juste
    # le header `X-Ovh-Application` (clé applicative). Pas de HMAC.
    #
    # Flux classique côté consommateur (ex: `beryl init`) :
    #   1. Construire la liste des `AccessRule` nécessaires
    #   2. `client.auth.request_consumer_key(rules)` → retourne une
    #      `ConsumerKey` avec `validation_url` et `consumer_key` (encore
    #      en `pendingValidation`)
    #   3. Afficher `validation_url` à l'utilisateur. Il ouvre son
    #      navigateur, se connecte à OVH, valide.
    #   4. La `consumer_key` est alors utilisable ; l'appelant la
    #      stocke (ex: dans `~/.beryl/.env.yml`).
    class Auth
      def initialize(@client : Client)
      end

      # Retourne les méta-données de la consumer key courante
      # (celle configurée dans le `Client`). `GET /auth/currentCredential`
      # renvoie notamment l'expiration — utile pour avertir l'utilisateur
      # combien de temps il reste avant de régénérer la clé.
      #
      # `expiration` peut être nil quand la clé a été créée en validité
      # illimitée. `last_use` peut aussi être nil si la clé vient d'être
      # validée et n'a jamais servi.
      def current_credential : CredentialInfo
        response = @client.call("GET", "/auth/currentCredential").not_nil!
        CredentialInfo.new(
          credential_id: response["credentialId"].as_i64,
          application_id: response["applicationId"].as_i64,
          creation: Time.parse_iso8601(response["creation"].as_s),
          expiration: response["expiration"]?.try(&.as_s?).try { |s| Time.parse_iso8601(s) },
          last_use: response["lastUse"]?.try(&.as_s?).try { |s| Time.parse_iso8601(s) },
          status: response["status"].as_s,
          ovh_support: response["ovhSupport"]?.try(&.as_bool?) || false,
        )
      end

      # Demande une consumer key OVH avec les droits exacts listés.
      # Chaque règle est un couple `{method, path}` (ex: `{"GET",
      # "/dedicated/server/*"}`). Les wildcards `*` sont supportés
      # par OVH (pattern "tout sous ce préfixe").
      #
      # `redirection` : URL vers laquelle OVH redirige le navigateur
      # de l'utilisateur une fois la clé validée. Optionnel. Si
      # omis, OVH affiche une page de confirmation simple.
      def request_consumer_key(
        rules : Array(AccessRule),
        redirection : String? = nil,
      ) : ConsumerKey
        body = {} of String => JSON::Any
        body["accessRules"] = JSON::Any.new(rules.map { |r| JSON::Any.new({
          "method" => JSON::Any.new(r.method),
          "path"   => JSON::Any.new(r.path),
        }) })
        body["redirection"] = JSON::Any.new(redirection) if redirection
        response = @client.call(
          "POST", "/auth/credential",
          body: body, app_only: true,
        ).not_nil!
        ConsumerKey.new(
          consumer_key: response["consumerKey"].as_s,
          validation_url: response["validationUrl"].as_s,
          state: response["state"].as_s,
        )
      end
    end

    # Règle d'accès OVH : une méthode HTTP + un path (wildcards autorisés).
    # Plus pratique qu'un Hash nu côté API publique.
    record AccessRule, method : String, path : String do
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "method", @method
          json.field "path", @path
        end
      end
    end

    # Résultat d'une demande de consumer key OVH. La clé n'est
    # utilisable qu'après que l'utilisateur a ouvert `validation_url`
    # et validé côté OVH (état `validated`). Avant, elle est
    # `pendingValidation`.
    record ConsumerKey,
      consumer_key : String,
      validation_url : String,
      state : String

    # Méta-données d'une consumer key (renvoyées par
    # `GET /auth/currentCredential`).
    #
    # `expiration` est nil pour les clés créées en validité illimitée.
    # `status` est typiquement `"validated"` pour une clé utilisable,
    # `"pendingValidation"` pour une clé pas encore confirmée côté OVH,
    # `"expired"` pour une clé périmée.
    record CredentialInfo,
      credential_id : Int64,
      application_id : Int64,
      creation : Time,
      expiration : Time?,
      last_use : Time?,
      status : String,
      ovh_support : Bool do
      # Nombre de jours restants avant l'expiration. Retourne nil si
      # la clé est en validité illimitée.
      def days_until_expiration : Int32?
        exp = @expiration
        return nil unless exp
        ((exp - Time.utc).total_days).to_i
      end
    end
  end
end

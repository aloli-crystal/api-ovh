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
  end
end

require "json"

module OvhApi
  module Endpoints
    # Endpoints `/me/sshKey`.
    #
    # Les clés SSH sont stockées au niveau du compte OVH (pas par serveur).
    # Elles sont identifiées par leur `keyName` (libre, imposé par
    # l'utilisateur à la création) ; la valeur complète (`key`) n'est
    # récupérable qu'en la demandant par nom.
    class SshKeys
      def initialize(@client : OvhApi::Client)
      end

      # Liste les noms de clés SSH du compte.
      #
      # `GET /me/sshKey` → `["laptop", "desktop", ...]`
      def list : Array(String)
        result = @client.call("GET", "/me/sshKey")
        result.try(&.as_a.map(&.as_s)) || [] of String
      end

      # Détail d'une clé.
      #
      # `GET /me/sshKey/{keyName}` → `OvhApi::SshKey`.
      def get(name : String) : SshKey
        result = @client.call("GET", "/me/sshKey/#{name}")
        SshKey.from_any(result.not_nil!)
      end

      # Ajoute une clé au compte.
      #
      # `POST /me/sshKey` avec `{keyName, key, default}`.
      #
      # * `name`     : nom libre, sert d'identifiant (attention, unique
      #                par compte).
      # * `key`      : valeur complète (`ssh-ed25519 AAAA... commentaire`).
      # * `default`  : si `true`, la clé est proposée par défaut dans les
      #                installations de serveurs dédiés.
      def create(name : String, key : String, default : Bool = false) : Nil
        @client.call(
          "POST",
          "/me/sshKey",
          body: {"keyName" => name, "key" => key, "default" => default},
        )
      end

      # Supprime une clé.
      #
      # `DELETE /me/sshKey/{keyName}`.
      def delete(name : String) : Nil
        @client.call("DELETE", "/me/sshKey/#{name}")
      end
    end

    # Détail d'une clé SSH OVH.
    struct SshKey
      getter key_name : String
      getter key : String
      getter default : Bool

      def initialize(@key_name : String, @key : String, @default : Bool)
      end

      def self.from_any(payload : JSON::Any) : SshKey
        new(
          key_name: payload["keyName"].as_s,
          key: payload["key"].as_s,
          default: payload["default"]?.try(&.as_bool?) || false,
        )
      end
    end
  end
end

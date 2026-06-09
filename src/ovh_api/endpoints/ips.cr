require "json"

module OvhApi
  module Endpoints
    # Endpoints `/ip/{ip}/reverse`.
    #
    # OVH gère le DNS inverse au niveau de chaque adresse IP plutôt que
    # par zone. Chaque IP peut porter un reverse unique (format FQDN
    # terminé par un point, standard RFC 1035).
    class Ips
      def initialize(@client : OvhApi::Client)
      end

      # Liste les IP pour lesquelles un reverse a été défini dans le bloc
      # qui contient `ip` (OVH renvoie les IPs du bloc, pas seulement
      # celle passée en argument).
      #
      # `GET /ip/{ip}/reverse` → liste d'IPs au format texte.
      def list(ip : String) : Array(String)
        result = @client.call("GET", "/ip/#{encode_ip(ip)}/reverse")
        result.try(&.as_a.map(&.as_s)) || [] of String
      end

      # Détail du reverse d'une IP.
      #
      # `GET /ip/{ip}/reverse/{ipReverse}` → `{ipReverse, reverse}`.
      def get_reverse(ip : String, ip_reverse : String) : Reverse
        result = @client.call("GET", "/ip/#{encode_ip(ip)}/reverse/#{ip_reverse}")
        Reverse.from_any(result.not_nil!)
      end

      # Définit le reverse d'une IP.
      #
      # `POST /ip/{ip}/reverse` avec `{ipReverse, reverse}`.
      #
      # * `ip`       : le bloc IP ou l'IP elle-même.
      # * `ip_reverse` : l'IP concrète à configurer (si `ip` est un bloc) ;
      #                  par défaut identique à `ip`.
      # * `reverse`  : le FQDN, *doit* se terminer par un point (`web01.aloli.fr.`).
      #
      # OVH valide que le FQDN résout bien sur l'IP avant d'accepter.
      def set_reverse(ip : String, reverse : String, ip_reverse : String? = nil) : Reverse
        target = ip_reverse || ip
        result = @client.call(
          "POST",
          "/ip/#{encode_ip(ip)}/reverse",
          body: {"ipReverse" => target, "reverse" => reverse},
        )
        Reverse.from_any(result.not_nil!)
      end

      # Supprime le reverse d'une IP.
      #
      # `DELETE /ip/{ip}/reverse/{ipReverse}`.
      def delete_reverse(ip : String, ip_reverse : String) : Nil
        @client.call("DELETE", "/ip/#{encode_ip(ip)}/reverse/#{ip_reverse}")
      end

      # Encode l'identifiant d'IP pour un segment de path. Un bloc CIDR
      # (ex. `2001:41d0:306:2b67::/64`, requis par OVH pour le reverse
      # IPv6) contient un `/` qui doit être encodé `%2F`, sinon il est
      # interprété comme séparateur de segments et l'API renvoie 404
      # « This service does not exist ». Les `:` d'une IPv6 sont des
      # pchar valides en RFC 3986 : on les laisse bruts (comme les `.`
      # d'une IPv4, qui passent déjà sans encodage).
      private def encode_ip(ip : String) : String
        ip.gsub('/', "%2F")
      end
    end

    # Enregistrement DNS inverse d'une IP.
    struct Reverse
      getter ip_reverse : String
      getter reverse : String

      def initialize(@ip_reverse : String, @reverse : String)
      end

      def self.from_any(payload : JSON::Any) : Reverse
        new(
          ip_reverse: payload["ipReverse"].as_s,
          reverse: payload["reverse"].as_s,
        )
      end
    end
  end
end

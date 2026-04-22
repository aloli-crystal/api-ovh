require "http/client"
require "openssl/hmac"
require "digest/sha1"
require "json"
require "uri"

require "./errors"

module OvhApi
  # Endpoints OVH officiels.
  #
  # `:eu` est la valeur par défaut (Europe continentale, marché principal
  # d'OVHcloud). Les clés API sont liées à un endpoint précis : une clé
  # créée sur eu.api.ovh.com ne fonctionnera pas sur ca.api.ovh.com.
  ENDPOINTS = {
    :eu            => "https://eu.api.ovh.com/1.0",
    :ca            => "https://ca.api.ovh.com/1.0",
    :us            => "https://api.us.ovhcloud.com/1.0",
    :kimsufi_eu    => "https://eu.api.kimsufi.com/1.0",
    :kimsufi_ca    => "https://ca.api.kimsufi.com/1.0",
    :soyoustart_eu => "https://eu.api.soyoustart.com/1.0",
    :soyoustart_ca => "https://ca.api.soyoustart.com/1.0",
  }

  # Transport HTTP abstrait. Permet d'injecter un double en test.
  #
  # Une implémentation doit retourner un tuple `{status, body}`. Le
  # `Client` se charge de décoder le JSON et de lever les exceptions.
  abstract class HttpTransport
    abstract def request(
      method : String,
      url : String,
      headers : HTTP::Headers,
      body : String,
    ) : {Int32, String}
  end

  # Transport par défaut, basé sur `HTTP::Client` de la stdlib.
  class DefaultHttpTransport < HttpTransport
    def request(method, url, headers, body) : {Int32, String}
      response = HTTP::Client.exec(
        method: method,
        url: url,
        headers: headers,
        body: body.empty? ? nil : body,
      )
      {response.status_code, response.body}
    end
  end

  # Client OVHcloud API v1.
  #
  # Chaque requête signée porte quatre en-têtes :
  #
  # * `X-Ovh-Application` : la clé publique de l'application.
  # * `X-Ovh-Consumer`    : le consumer key (jeton utilisateur).
  # * `X-Ovh-Timestamp`   : timestamp Unix, resynchronisé avec le serveur.
  # * `X-Ovh-Signature`   : `"$1$" + SHA1_HEX(secret + "+" + consumer
  #                         + "+" + method + "+" + url + "+" + body
  #                         + "+" + timestamp)`.
  #
  # La signature est calculée sur l'URL complète (avec query string si
  # présente) et sur le corps JSON exact envoyé. Toute divergence, même
  # d'un espace, invalide la signature.
  class Client
    getter application_key : String
    getter application_secret : String
    getter consumer_key : String?
    getter endpoint : String

    # Offset entre l'horloge locale et celle d'OVH (secondes).
    # Résolu à la première requête signée, réutilisé ensuite pour éviter
    # des allers-retours inutiles. La fenêtre tolérée par OVH est de
    # 30 secondes côté production.
    property time_delta : Int64?

    # Injection du transport HTTP (par défaut `DefaultHttpTransport`).
    # En test, passer un double qui renvoie `{status, body}` prédéfini.
    property transport : HttpTransport

    def initialize(
      @application_key : String,
      @application_secret : String,
      @consumer_key : String? = nil,
      endpoint : Symbol | String = :eu,
      @transport : HttpTransport = DefaultHttpTransport.new,
    )
      @endpoint = resolve_endpoint(endpoint)
    end

    private def resolve_endpoint(endpoint) : String
      case endpoint
      in Symbol
        ENDPOINTS[endpoint]? || raise ArgumentError.new(
          "Endpoint OVH inconnu : #{endpoint.inspect}. Valeurs possibles : " \
          "#{ENDPOINTS.keys.map(&.inspect).join(", ")}.",
        )
      in String
        endpoint
      end
    end

    # Horodatage serveur OVH.
    #
    # OVH expose `/1.0/auth/time` en non-signé qui renvoie un entier Unix.
    # On l'utilise pour calculer un offset avec l'horloge locale plutôt
    # que de requérir à chaque appel : l'offset est stable pendant la
    # durée de vie du process.
    def server_time : Int64
      local = Time.utc.to_unix
      if delta = @time_delta
        return local + delta
      end

      status, body = @transport.request(
        method: "GET",
        url: "#{@endpoint}/auth/time",
        headers: HTTP::Headers{"Accept" => "application/json"},
        body: "",
      )
      unless (200..299).includes?(status)
        raise ApiError.new(
          "Impossible de récupérer /auth/time (HTTP #{status}) : #{body}",
          status,
        )
      end
      remote = body.strip.to_i64
      @time_delta = remote - local
      remote
    end

    # Calcul de la signature OVH.
    #
    # ```
    # sig = "$1$" + sha1_hex(secret + "+" + consumer + "+" + method
    #                        + "+" + url + "+" + body + "+" + timestamp)
    # ```
    #
    # Public pour permettre les tests unitaires avec des vecteurs
    # déterministes. En usage normal, c'est `call` qui l'invoque.
    def sign(method : String, url : String, body : String, timestamp : Int64 | String, consumer : String) : String
      payload = {
        @application_secret,
        consumer,
        method,
        url,
        body,
        timestamp.to_s,
      }.join("+")
      "$1$" + Digest::SHA1.hexdigest(payload)
    end

    # Effectue un appel API.
    #
    # * `method`      : `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`.
    # * `path`        : chemin relatif au endpoint (ex. `"/me/sshKey"`).
    # * `query`       : table de paramètres encodée dans l'URL.
    # * `body`        : objet JSON-sérialisable (ou nil).
    # * `auth`        : `true` pour les endpoints nécessitant une signature
    #                    (toutes les routes utilisateur). `false` pour
    #                    `/auth/time` et quelques rares endpoints publics.
    #
    # Retourne le corps parsé en `JSON::Any` (ou `nil` si corps vide).
    def call(
      method : String,
      path : String,
      query : Hash(String, String)? = nil,
      body = nil,
      auth : Bool = true,
    ) : JSON::Any?
      url = build_url(path, query)
      body_str = serialize_body(body)
      headers = HTTP::Headers{
        "Accept"       => "application/json",
        "Content-Type" => "application/json",
      }

      if auth
        ck = @consumer_key || raise AuthenticationError.new(
          "Un consumer_key est requis pour appeler #{method} #{path}.",
        )
        ts = server_time
        headers["X-Ovh-Application"] = @application_key
        headers["X-Ovh-Consumer"] = ck
        headers["X-Ovh-Timestamp"] = ts.to_s
        headers["X-Ovh-Signature"] = sign(method, url, body_str, ts, ck)
      end

      status, response_body = @transport.request(method, url, headers, body_str)
      handle_response(status, response_body, method, path)
    end

    private def build_url(path : String, query : Hash(String, String)?) : String
      full = @endpoint + (path.starts_with?("/") ? path : "/#{path}")
      if query && !query.empty?
        pairs = query.map { |k, v| "#{URI.encode_path_segment(k)}=#{URI.encode_path_segment(v)}" }
        full + "?" + pairs.join("&")
      else
        full
      end
    end

    private def serialize_body(body) : String
      case body
      when Nil
        ""
      when String
        body
      else
        body.to_json
      end
    end

    private def handle_response(status : Int32, body : String, method : String, path : String) : JSON::Any?
      case status
      when 200..299
        return nil if body.empty?
        JSON.parse(body)
      when 401, 403
        raise AuthenticationError.new(format_error(status, body, method, path))
      when 404
        raise NotFound.new(format_error(status, body, method, path))
      when 429
        retry_after = nil
        begin
          parsed = JSON.parse(body)
          retry_after = parsed["retryAfter"]?.try(&.as_i?)
        rescue
        end
        raise RateLimited.new(format_error(status, body, method, path), retry_after)
      else
        error_code = extract_error_code(body)
        raise ApiError.new(format_error(status, body, method, path), status, error_code)
      end
    end

    private def format_error(status : Int32, body : String, method : String, path : String) : String
      "OVH API #{method} #{path} → HTTP #{status} : #{body.empty? ? "(corps vide)" : body}"
    end

    private def extract_error_code(body : String) : String?
      parsed = JSON.parse(body)
      parsed["errorCode"]?.try(&.as_s?) || parsed["class"]?.try(&.as_s?)
    rescue
      nil
    end

    # Accès paresseux aux endpoints. Chaque sous-client réutilise le même
    # `self`, donc la même config, la même signature, le même transport.

    def ssh_keys : Endpoints::SshKeys
      @ssh_keys ||= Endpoints::SshKeys.new(self)
    end

    def dedicated_servers : Endpoints::DedicatedServers
      @dedicated_servers ||= Endpoints::DedicatedServers.new(self)
    end

    def ips : Endpoints::Ips
      @ips ||= Endpoints::Ips.new(self)
    end

    def domains : Endpoints::Domains
      @domains ||= Endpoints::Domains.new(self)
    end

    @ssh_keys : Endpoints::SshKeys?
    @dedicated_servers : Endpoints::DedicatedServers?
    @ips : Endpoints::Ips?
    @domains : Endpoints::Domains?
  end
end

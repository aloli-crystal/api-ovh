module OvhApi
  # Base de la hiérarchie d'exceptions OvhApi.
  #
  # Toutes les erreurs remontées par ce shard descendent de `OvhApi::Error`,
  # ce qui permet à l'appelant de rattraper l'ensemble avec un seul `rescue`.
  class Error < Exception
  end

  # Erreur d'authentification : clé applicative, secret ou consumer key
  # invalide / expiré. Correspond à HTTP 401/403 côté OVH.
  class AuthenticationError < Error
  end

  # Ressource inexistante. Correspond à HTTP 404.
  class NotFound < Error
  end

  # Dépassement de quota. Correspond à HTTP 429.
  class RateLimited < Error
    getter retry_after : Int32?

    def initialize(message : String, @retry_after : Int32? = nil)
      super(message)
    end
  end

  # Erreur générique remontée par l'API OVH : message, code HTTP et
  # classe d'erreur OVH (champ `errorCode` du corps JSON si présent).
  class ApiError < Error
    getter http_status : Int32
    getter error_code : String?

    def initialize(message : String, @http_status : Int32, @error_code : String? = nil)
      super(message)
    end
  end
end

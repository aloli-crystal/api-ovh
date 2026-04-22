require "json"

module OvhApi
  module Endpoints
    # Endpoints `/domain/zone/{zoneName}/...` — gestion des
    # enregistrements DNS d'une zone hébergée chez OVH.
    #
    # Les modifications sur une zone passent par un cycle :
    #   1. créer / modifier / supprimer des records (`records`, `create_record`,
    #      `update_record`, `delete_record`)
    #   2. `refresh(zone)` pour propager les changements
    #
    # Sans `refresh`, les modifications restent dans la DB OVH mais ne
    # sont pas publiées aux serveurs DNS.
    class Domains
      def initialize(@client : OvhApi::Client)
      end

      # Liste tous les records d'une zone, optionnellement filtrés par
      # type de champ (A, AAAA, CNAME, MX…) et/ou par sous-domaine.
      #
      # `GET /domain/zone/{zone}/record` → array d'IDs (Int64) que l'on
      # peut ensuite passer à `record/1` pour récupérer les détails.
      def records(
        zone : String,
        field_type : String? = nil,
        sub_domain : String? = nil,
      ) : Array(Int64)
        query = {} of String => String
        query["fieldType"] = field_type if field_type
        query["subDomain"] = sub_domain if sub_domain
        result = @client.call(
          "GET",
          "/domain/zone/#{zone}/record",
          query: query.empty? ? nil : query,
        )
        result.try(&.as_a.map(&.as_i64)) || [] of Int64
      end

      # Détail d'un record (subDomain, fieldType, target, ttl, id).
      #
      # `GET /domain/zone/{zone}/record/{id}` → `OvhApi::DomainRecord`.
      def record(zone : String, id : Int64 | Int32) : DomainRecord
        result = @client.call("GET", "/domain/zone/#{zone}/record/#{id}")
        DomainRecord.from_any(result.not_nil!)
      end

      # Crée un record dans la zone.
      #
      # `POST /domain/zone/{zone}/record` avec `{fieldType, subDomain, target, ttl?}`.
      #
      # Le record n'est publié qu'après un `refresh(zone)`.
      def create_record(
        zone : String,
        field_type : String,
        sub_domain : String,
        target : String,
        ttl : Int32? = nil,
      ) : DomainRecord
        body = {} of String => String | Int32
        body["fieldType"] = field_type
        body["subDomain"] = sub_domain
        body["target"] = target
        body["ttl"] = ttl if ttl
        result = @client.call(
          "POST",
          "/domain/zone/#{zone}/record",
          body: body,
        )
        DomainRecord.from_any(result.not_nil!)
      end

      # Modifie un record existant.
      #
      # `PUT /domain/zone/{zone}/record/{id}` avec `{subDomain?, target?, ttl?}`.
      #
      # Le fieldType d'un record ne se change pas (il faut créer un
      # nouveau record et supprimer l'ancien). Les champs non fournis
      # conservent leur valeur.
      def update_record(
        zone : String,
        id : Int64 | Int32,
        sub_domain : String? = nil,
        target : String? = nil,
        ttl : Int32? = nil,
      ) : Nil
        body = {} of String => String | Int32
        body["subDomain"] = sub_domain if sub_domain
        body["target"] = target if target
        body["ttl"] = ttl if ttl
        @client.call("PUT", "/domain/zone/#{zone}/record/#{id}", body: body)
      end

      # Supprime un record.
      #
      # `DELETE /domain/zone/{zone}/record/{id}`.
      def delete_record(zone : String, id : Int64 | Int32) : Nil
        @client.call("DELETE", "/domain/zone/#{zone}/record/#{id}")
      end

      # Propage les modifications récentes sur la zone aux serveurs DNS.
      # À appeler après un create/update/delete de record.
      #
      # `POST /domain/zone/{zone}/refresh`.
      def refresh(zone : String) : Nil
        @client.call("POST", "/domain/zone/#{zone}/refresh")
      end

      # Idempotent : s'assure qu'un record (field_type, sub_domain) pointe
      # bien sur `target`. Crée s'il n'existe pas, update si la cible
      # diffère, ne fait rien sinon. Retourne le record final.
      #
      # Utile pour automatiser la mise en place d'un A/AAAA/CNAME sans
      # avoir à gérer manuellement le cycle de vie (ajout/mise à jour/dédup).
      def ensure_record(
        zone : String,
        field_type : String,
        sub_domain : String,
        target : String,
        ttl : Int32? = nil,
      ) : DomainRecord
        ids = records(zone, field_type: field_type, sub_domain: sub_domain)
        ids.each do |id|
          rec = record(zone, id)
          if rec.target == target
            return rec
          else
            update_record(zone, id, target: target, ttl: ttl)
            return record(zone, id)
          end
        end
        create_record(zone, field_type, sub_domain, target, ttl: ttl)
      end
    end

    # Un enregistrement DNS dans une zone OVH.
    struct DomainRecord
      getter id : Int64
      getter zone : String
      getter sub_domain : String
      getter field_type : String
      getter target : String
      getter ttl : Int32

      def initialize(@id, @zone, @sub_domain, @field_type, @target, @ttl)
      end

      def self.from_any(payload : JSON::Any) : DomainRecord
        new(
          id: payload["id"].as_i64,
          zone: payload["zone"].as_s,
          sub_domain: payload["subDomain"]?.try(&.as_s?) || "",
          field_type: payload["fieldType"].as_s,
          target: payload["target"].as_s,
          ttl: payload["ttl"]?.try(&.as_i?) || 0,
        )
      end

      # Reconstitue le FQDN « subDomain.zone » pour affichage.
      def fqdn : String
        sub_domain.empty? ? zone : "#{sub_domain}.#{zone}"
      end
    end
  end
end

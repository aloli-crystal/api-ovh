require "./ovh_api/version"
require "./ovh_api/errors"
require "./ovh_api/endpoints/ssh_keys"
require "./ovh_api/endpoints/dedicated_servers"
require "./ovh_api/endpoints/ips"
require "./ovh_api/endpoints/domains"
require "./ovh_api/client"

# OvhApi — client Crystal pur (stdlib uniquement) pour l'API OVHcloud v1.
#
# Couvre le strict nécessaire au provisioning de serveurs dédiés :
#
# * `client.ssh_keys`          — lister / créer / supprimer les clés SSH du compte.
# * `client.dedicated_servers` — lister les serveurs, lancer une réinstallation,
#                                suivre la tâche, renommer (displayName), lister
#                                les IPs allouées.
# * `client.ips`               — lire et écrire le DNS inverse des IPs.
# * `client.domains`           — gérer les enregistrements DNS d'une zone
#                                (A/AAAA/CNAME/MX…), rafraîchir la zone.
#
# ```
# require "ovh-api"
#
# client = OvhApi::Client.new(
#   application_key: ENV["OVH_APPLICATION_KEY"],
#   application_secret: ENV["OVH_APPLICATION_SECRET"],
#   consumer_key: ENV["OVH_CONSUMER_KEY"],
#   endpoint: :eu,
# )
#
# client.ssh_keys.create(name: "laptop", key: "ssh-ed25519 AAAA...")
#
# task = client.dedicated_servers.reinstall(
#   service_name: "ns1234.ip-1-2-3.eu",
#   template: "debian12_64",
#   hostname: "web01.aloli.fr",
#   ssh_key_name: "laptop",
# )
#
# loop do
#   status = client.dedicated_servers.task(
#     service_name: "ns1234.ip-1-2-3.eu",
#     task_id: task.id,
#   )
#   break if status.done?
#   sleep 30
# end
# ```
module OvhApi
end

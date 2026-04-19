require "../src/ovh_api"

# Exemple end-to-end : installation Debian 12 sur le premier serveur dédié
# du compte, et lecture du DNS inverse à la fin.
#
# Variables d'environnement requises :
#   OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY
#
# Créer ces clés sur https://eu.api.ovh.com/createApp/ et
# https://eu.api.ovh.com/createToken/ (scopes GET /me/sshKey,
# POST /me/sshKey, GET /dedicated/server/*, POST /dedicated/server/*/reinstall,
# GET /dedicated/server/*/task, GET /dedicated/server/*/task/*,
# POST /ip/*/reverse).
#
# Usage :
#   crystal run examples/provision_debian.cr
#
# Par sécurité, ce fichier ne *déclenche* pas l'installation sans une
# variable OVH_CONFIRM=yes. Une réinstallation efface le serveur.

APPLICATION_KEY    = ENV["OVH_APPLICATION_KEY"]? || ""
APPLICATION_SECRET = ENV["OVH_APPLICATION_SECRET"]? || ""
CONSUMER_KEY       = ENV["OVH_CONSUMER_KEY"]? || ""
CONFIRM            = ENV["OVH_CONFIRM"]? == "yes"
HOSTNAME           = ENV["TARGET_HOSTNAME"]? || "web01.aloli.fr"
SSH_KEY_NAME       = ENV["SSH_KEY_NAME"]? || "laptop"

if APPLICATION_KEY.empty? || APPLICATION_SECRET.empty? || CONSUMER_KEY.empty?
  STDERR.puts "Credentials OVH manquants. Positionnez OVH_APPLICATION_KEY, " \
              "OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY."
  exit 2
end

client = OvhApi::Client.new(
  application_key: APPLICATION_KEY,
  application_secret: APPLICATION_SECRET,
  consumer_key: CONSUMER_KEY,
  endpoint: :eu,
)

# 1. Vérifier la présence de la clé SSH sur le compte.
puts "Clés SSH déclarées :"
keys = client.ssh_keys.list
keys.each { |k| puts "  - #{k}" }
unless keys.includes?(SSH_KEY_NAME)
  STDERR.puts "La clé SSH « #{SSH_KEY_NAME} » n'existe pas sur le compte."
  STDERR.puts "Ajoutez-la d'abord via client.ssh_keys.create(...)."
  exit 3
end

# 2. Choisir le premier serveur dédié du compte (exemple simpliste).
servers = client.dedicated_servers.list
if servers.empty?
  STDERR.puts "Aucun serveur dédié sur ce compte."
  exit 4
end
service_name = servers.first
puts "Serveur cible : #{service_name}"

# 3. Récupérer l'état actuel.
info = client.dedicated_servers.info(service_name)
puts "État : #{info["state"]?}"
puts "Reverse actuel : #{info["reverse"]?}"

# 4. Vérifier que le template Debian 12 est disponible.
templates = client.dedicated_servers.installation_templates
unless templates.includes?("debian12_64")
  STDERR.puts "Le template debian12_64 n'est pas disponible. Templates :"
  templates.first(10).each { |t| STDERR.puts "  - #{t}" }
  exit 5
end

if !CONFIRM
  puts
  puts "OVH_CONFIRM=yes non défini → arrêt avant la réinstallation."
  puts "Relancez avec OVH_CONFIRM=yes pour déclencher l'installation."
  exit 0
end

# 5. Lancer la réinstallation.
puts "Lancement de la réinstallation Debian 12 sur #{service_name}..."
task = client.dedicated_servers.reinstall(
  service_name: service_name,
  template: "debian12_64",
  hostname: HOSTNAME,
  ssh_key_name: SSH_KEY_NAME,
)
puts "Tâche #{task.id} créée (#{task.function}, état #{task.status})."

# 6. Poll toutes les 30 secondes.
loop do
  sleep 30.seconds
  task = client.dedicated_servers.task(service_name: service_name, task_id: task.id)
  puts "[#{Time.utc}] tâche #{task.id} → #{task.status}"
  break if task.done?
end

if task.success?
  puts "Installation terminée avec succès."
else
  STDERR.puts "Échec : #{task.status} (#{task.comment})"
  exit 6
end

# 7. Définir le DNS inverse.
info = client.dedicated_servers.info(service_name)
ip = info["ip"]?.try(&.as_s?)
if ip
  reverse = HOSTNAME.ends_with?(".") ? HOSTNAME : "#{HOSTNAME}."
  puts "Pose du reverse #{reverse} sur #{ip}..."
  client.ips.set_reverse(ip: ip, reverse: reverse)
  puts "Reverse posé."
end

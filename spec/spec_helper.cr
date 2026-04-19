require "spec"
require "../src/ovh_api"

# Transport HTTP factice : stocke les requêtes reçues et renvoie des
# réponses pré-programmées. Purement stdlib, aucune dépendance externe.
#
# Usage dans les specs :
#
# ```
# transport = FakeTransport.new
# transport.stub("GET", /auth\/time/, status: 200, body: "1700000000")
# transport.stub("GET", /me\/sshKey/, status: 200, body: %(["laptop"]))
#
# client = OvhApi::Client.new(
#   application_key: "app",
#   application_secret: "secret",
#   consumer_key: "ck",
#   transport: transport,
# )
# client.ssh_keys.list.should eq(["laptop"])
#
# # Inspection des requêtes émises :
# transport.requests.last.headers["X-Ovh-Signature"].should start_with("$1$")
# ```
class FakeTransport < OvhApi::HttpTransport
  record Request,
    method : String,
    url : String,
    headers : HTTP::Headers,
    body : String

  record Stub,
    method : String,
    url_pattern : Regex,
    status : Int32,
    body : String

  getter requests = [] of Request
  getter stubs = [] of Stub

  def stub(method : String, url_pattern : Regex, status : Int32, body : String) : Nil
    @stubs << Stub.new(method: method, url_pattern: url_pattern, status: status, body: body)
  end

  def request(method, url, headers, body) : {Int32, String}
    @requests << Request.new(method: method, url: url, headers: headers, body: body)

    match = @stubs.reverse.find { |s| s.method == method && s.url_pattern.matches?(url) }
    unless match
      raise "Aucun stub ne correspond à #{method} #{url} (stubs déclarés : " \
            "#{@stubs.map { |s| "#{s.method} #{s.url_pattern.source}" }.join(", ")})"
    end
    {match.status, match.body}
  end
end

# Fabrique un client lié à un FakeTransport, avec /auth/time déjà stubbé
# (renvoie `1700000000` par défaut, valeur utilisée dans les vecteurs
# de signature).
def build_client(transport : FakeTransport, time : Int64 = 1_700_000_000_i64) : OvhApi::Client
  transport.stub("GET", /auth\/time/, status: 200, body: time.to_s)
  OvhApi::Client.new(
    application_key: "app-key",
    application_secret: "app-secret",
    consumer_key: "consumer-key",
    endpoint: :eu,
    transport: transport,
  )
end

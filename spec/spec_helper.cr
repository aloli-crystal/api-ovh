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

  # Stub à réponse fixe (cas standard).
  class Stub
    getter method : String
    getter url_pattern : Regex

    def initialize(@method : String, @url_pattern : Regex, @status : Int32, @body : String)
    end

    def next : {Int32, String}
      {@status, @body}
    end
  end

  # Stub qui rend une séquence de réponses successives sur une même URL.
  # Le dernier élément reste collant (renvoyé pour tous les appels
  # ultérieurs au-delà de la séquence). Sert à tester `wait_for_task` :
  # plusieurs polls sur la même URL doivent voir la `Task` évoluer.
  class SequenceStub
    getter method : String
    getter url_pattern : Regex

    def initialize(
      @method : String,
      @url_pattern : Regex,
      @responses : Array({Int32, String}),
    )
      @index = 0
    end

    def next : {Int32, String}
      response = @responses[@index]
      @index += 1 if @index < @responses.size - 1
      response
    end
  end

  alias AnyStub = Stub | SequenceStub

  getter requests = [] of Request
  getter stubs = [] of AnyStub

  def stub(method : String, url_pattern : Regex, status : Int32, body : String) : Nil
    @stubs << Stub.new(method: method, url_pattern: url_pattern, status: status, body: body)
  end

  def stub_sequence(method : String, url_pattern : Regex, responses : Array({Int32, String})) : Nil
    raise "stub_sequence : il faut au moins une réponse" if responses.empty?
    @stubs << SequenceStub.new(method: method, url_pattern: url_pattern, responses: responses)
  end

  def request(method, url, headers, body) : {Int32, String}
    @requests << Request.new(method: method, url: url, headers: headers, body: body)

    match = @stubs.reverse.find { |s| s.method == method && s.url_pattern.matches?(url) }
    unless match
      raise "Aucun stub ne correspond à #{method} #{url} (stubs déclarés : " \
            "#{@stubs.map { |s| "#{s.method} #{s.url_pattern.source}" }.join(", ")})"
    end
    match.next
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

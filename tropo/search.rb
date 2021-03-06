require 'rubygems'
require 'net/http'
require 'json'

module Rest
  # adapted from http://wiki.apache.org/couchdb/Getting_started_with_Ruby
  class Server
    def initialize(host, port, options = nil)
      @host = host
      @port = port
      @options = options || {}
    end

    def get(uri)
      request(Net::HTTP::Get.new(uri))
    end

    def put(uri, json)
      req = Net::HTTP::Put.new(uri)
      req["content-type"] = "application/json"
      req.body = json
      request(req)
    end

    def post(uri, json)
      req = Net::HTTP::Post.new(uri)
      req["content-type"] = "application/json"
      req.body = json
      request(req)
    end

    def request(req)
      req.basic_auth @options['user'], @options['pass'] if (@options['user'] && @options['pass'])
      Net::HTTP.start(@host, @port) { |http| http.request(req) }
    end
  end
end

@cities = {
  "12063970792" => "Seattle",
  "14158898462" => "San Francisco",
  "14157660887" => "Oakland",
  "15035759494" => "Portland"
}

@search = Rest::Server.new "open211.org", 80
@numbers = Rest::Server.new "yourcouch", 80, {"user" => "user", "pass" => "pass"}
@number = $currentCall.callerID.to_s
@initialText = $currentCall.initialText.downcase
@next_page = %w{next n N NEXT Next}.include? @initialText

def get_last_search
  res = @numbers.get "/open211_messages/" + @number
  if res.kind_of?(Net::HTTPNotFound)
    @last_search = false 
  else
    @last_search = JSON.parse res.body
  end
  @last_search
end

def get_page_number
  if @last_search = get_last_search
    return @last_search['page']
  else
    return 1
  end
end

def get_query
  if @next_page
    return @last_search['query']
  else
    return  @initialText
  end
end

def update_last_search(data)
  @last_search = get_last_search unless @last_search
  data = {"page" => 1, "query" => @query} unless @next_page
  data['query'] = @last_search['query'] if @last_search && @next_page
  data['_rev'] = @last_search['_rev'] if @last_search
  data['_id'] = @number
  res = @numbers.post "/open211_messages/", data.to_json
  JSON.parse res.body
end

def search(query, offset)
  query_json = {
    "size" => offset.to_i,
    "query" => {
      "query_string" => {
        "fields" => ["name", "description"],
        "query" => query
      }
    },
    "filter" => {
      "query" => {
        "query_string" => {
          "default_field" => "city",
          "query" => "Oakland"
        }
      }
    }
  }
  response = @search.post "/api/search", query_json.to_json
  results = JSON.parse response.body
  results['hits']['hits'][-1]['_source']
end

def compose_response(hit)
  response = ""
  %w(name organization phone address hours).each do |attribute|
    if hit[attribute]
      msg = hit[attribute]
      msg = msg[0..50] + "..." if hit[attribute].length > 40
      response << "#{msg} " if msg.length > 0 && !response.match(msg)
    end
  end
  
  response = "#{response}. txt back n for more"
end

def perform_search
  @page = get_page_number
  @query = get_query
  hit = search @query, @page
  response = compose_response hit
  say response
  update_last_search("page" => @page + 1, "query" => @query)
end

if $currentCall.channel == "TEXT"
  begin
    perform_search
  rescue
    log "Error while processing #{$currentCall.initialText} from #{$currentCall.callerID}"
  end
end

hangup
require 'json'
require 'net/http'
require 'openssl'
require 'rack'
require 'sinatra'
require 'uri'

config = JSON.parse(File.read('config.json'))

# GitHub webhook secret
$gh_secret = config['github']['secret']

set :port, config['port']

# Slack webhook URIs
opened_uri = URI(config['slack']['webhooks']['opened'])
merged_uri = URI(config['slack']['webhooks']['merged'])

helpers do
     def verify_signature(payload_body, signature_from_header)
          puts $gh_secret
          puts 
          signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA1.new, $gh_secret, payload_body)
          return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, signature_from_header)
     end

     def make_json(repo, number, author, action, sender, emoji)
          { "text" =>
            "PR #{number} of #{repo} by #{author} #{action} by #{sender} :#{emoji}:"
          }.to_json
     end

     def notify_json(to_uri, json_payload)
          Net::HTTP.post to_uri,
               json_payload,
               "Content-Type" => "application/json"
     end
end

post '/payload' do
     request.body.rewind
     payload_body = request.body.read
     body = JSON.parse payload_body
     
     verify_signature(payload_body, request.env['HTTP_X_HUB_SIGNATURE'])

     # PR action details
     action = body['action']
     sender = body['sender']['login'] 
     
     # Get the PR details
     pr = body['pull_request']
     repo = body['repository']['full_name']
     number =  body['number']
     title =   pr['title']
     author =  pr['user']['login']
     merged =  pr['merged']

     # PR opened
     if action == 'opened'
          notify_json opened_uri,
               make_json(repo, number, author, action, sender, "CR")
          'PR opened'
     # PR merged
     elsif (action == 'closed') && merged
          action = "merged"
          notify_json merged_uri,
               make_json(repo, number, author, action, sender, "shipit")
          'PR merged'
     # PR closed without merging
     elsif (action == 'closed') && !merged
          'PR closed without merging'
     end
end


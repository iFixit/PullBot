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
          signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA1.new, $gh_secret, payload_body)
          return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, signature_from_header)
     end

     def make_merged_json(repo_meta, pr, author_meta, action, sender_meta)
          j = { 
               "blocks" => [
                    { 
                         "type" => "section",
                         "text" => {
                              "type" => "mrkdwn",
                              "text" => "<#{repo_meta['html_url']}|#{repo_meta['full_name']}>"\
                                        " <#{pr['html_url']}|#{pr['title']} ##{pr['number']}>"
                         }
                    },
                    {
                         "type" => "context",
                         "elements" => [
                              {
                                   "type" => "image",
                                   "image_url" => author_meta['avatar_url'],
                                   "alt_text" => author_meta['login']
                              },
                              {
                                   "type" => "mrkdwn",
                                   "text" => "by <#{author_meta['html_url']}|#{author_meta['login']}>"
                              },
                              {
                                   "type" => "image",
                                   "image_url" => sender_meta['avatar_url'],
                                   "alt_text" => sender_meta['login']
                              },
                              {
                                   "type" => "mrkdwn",
                                   "text" => " merged by <#{sender_meta['html_url']}|#{sender_meta['login']}>"
                              }
                         ]
                    }
               ]
          }
          j.to_json
     end

     def notify_json(to_uri, json_payload)
          r = Net::HTTP.post to_uri,
               json_payload,
               "Content-Type" => "application/json"
          puts r.body
     end
end

post '/payload' do
     request.body.rewind
     payload_body = request.body.read
     body = JSON.parse payload_body
     
     verify_signature(payload_body, request.env['HTTP_X_HUB_SIGNATURE'])

     # PR action details
     action = body['action']
     
     # Get the PR details
     pr = body['pull_request']
     merged =  pr['merged']

     pr_link = pr['html_url']
     repo_meta = body['repository']
     author_meta = pr['user']
     sender_meta = body['sender']

     # PR opened
     if action == 'opened'
          notify_json opened_uri,
               make_merged_json(repo_meta, pr, author_meta, action, sender_meta)
     # PR merged
     elsif (action == 'closed') && merged
          action = "merged"
          notify_json merged_uri,
               make_merged_json(repo_meta, pr, author_meta, action, sender_meta)
     # PR closed without merging
     elsif (action == 'closed') && !merged
          notify_json opened_uri,
               make_merged_json(repo_meta, pr, author_meta, action, sender_meta)
     end
     'Payload receieved'
end


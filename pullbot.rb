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

# PR Icon URIs
$pr_icon_closed_uri = config['slack']['images']['closed']
$pr_icon_opened_uri = config['slack']['images']['opened']
$pr_icon_merged_uri = config['slack']['images']['merged']


helpers do
     def verify_signature(payload_body, signature_from_header)
          signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA1.new, $gh_secret, payload_body)
          return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, signature_from_header)
     end

     def make_merged_json(repo_meta, pr, author_meta, action, sender_meta, pr_icon_uri)
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
                                   "text" => " #{action} by <#{sender_meta['html_url']}|#{sender_meta['login']}>"
                              },
                              {
                                   "type" => "image",
                                   "image_url" => "#{pr_icon_uri}",
                                   "alt_text" => "#{action}"
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
          icon_uri = $pr_icon_opened_uri
          notify_json opened_uri,
               make_merged_json(repo_meta, pr, author_meta, action, sender_meta, icon_uri)
     # PR merged
     elsif (action == 'closed') && merged
          action = "merged"
          icon_uri = $pr_icon_merged_uri
          notify_json merged_uri,
               make_merged_json(repo_meta, pr, author_meta, action, sender_meta, icon_uri)
     # PR closed without merging
     elsif (action == 'closed') && !merged
          icon_uri = $pr_icon_closed_uri
          notify_json opened_uri,
               make_merged_json(repo_meta, pr, author_meta, action, sender_meta, icon_uri)
     end
     'Payload receieved'
end


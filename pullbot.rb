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
$closed_uri = URI(config['slack']['webhooks']['closed'])
$opened_uri = URI(config['slack']['webhooks']['opened'])
$merged_uri = URI(config['slack']['webhooks']['merged'])

# PR Icon URIs
$pr_icon_closed_uri = config['slack']['images']['closed']
$pr_icon_opened_uri = config['slack']['images']['opened']
$pr_icon_merged_uri = config['slack']['images']['merged']

# PR announcement edge colors
$edge_color_opened = config['slack']['edge_colors']['opened']
$edge_color_merged = config['slack']['edge_colors']['merged']
$edge_color_closed = config['slack']['edge_colors']['closed']

helpers do
     def verify_signature(payload_body, signature_from_header)
          signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA1.new, $gh_secret, payload_body)
          return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, signature_from_header)
     end

     def make_json(repo_meta, pr, author_meta, action, sender_meta, pr_icon_uri, attachment, edge_color)
          j = {
               "blocks" => [
                    {
                         "type" => "divider"
                    },
                    {
                         "type" => "context",
                         "elements" => [
                              {
                                   "type" => "image",
                                   "image_url" => "#{pr_icon_uri}",
                                   "alt_text" => "#{action}"
                              },
                              {
                                   "type" => "mrkdwn",
                                   "text" => "Pull request #{action}"
                              }
                         ]
                    },
                    {
                         "type" => "section",
                         "text" => {
                              "type" => "mrkdwn",
                              "text" => "*[<#{repo_meta['html_url']}|#{repo_meta['full_name']}>]*"\
                                        " <#{pr['html_url']}|_#{pr['title']}_ *##{pr['number']}*>"
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
                              }
                         ]
                    },
                    {
                         "type" => "divider"
                    }
               ]
          }
          if (attachment)
               j["attachments"] = [
                    {
                    "color" => "#{edge_color}",
                    "blocks" => [
                              {
                                   "type" => "section",
                                   "text" => {
                                        "type" => "mrkdwn",
                                        "text" => "#{pr['body']}"
                                   }
                              }
                         ]
                    }
               ]
          end
          j.to_json
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

     # Get the PR details
     pr = body['pull_request']
     merged =  pr['merged']

     pr_link = pr['html_url']
     repo_meta = body['repository']
     author_meta = pr['user']
     sender_meta = body['sender']

     # Whether to show the PR description
     attachment = false

     # PR opened
     if action == 'opened'
          webhook_uri = $opened_uri
          icon_uri = $pr_icon_opened_uri
          color = $edge_color_opened
          attachment = true
          response = 'Opened PR message receieved'
     # PR re-opened
     elsif action == 'reopened'
          action = 'reopened'
          webhook_uri = $opened_uri
          icon_uri = $pr_icon_opened_uri
          color = $edge_color_opened
          response = 'Reopened PR message receieved'
     # PR merged
     elsif (action == 'closed') && merged
          action = "merged"
          webhook_uri = $merged_uri
          icon_uri = $pr_icon_merged_uri
          color = $edge_color_merged
          response = 'Merged PR message receieved'
     # PR closed without merging
     elsif (action == 'closed') && !merged
          action = "closed without merge"
          webhook_uri = $closed_uri
          icon_uri = $pr_icon_closed_uri
          color = $edge_color_clsoed
          response = 'Closed PR message receieved'
     end
     notify_json webhook_uri,
          make_json(repo_meta, pr, author_meta, action, sender_meta, icon_uri, attachment, color)
     response
end


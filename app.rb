require 'sinatra'
require 'json'

config = JSON.parse(File.read('config.json'))

get '/' do
     'Hello world!'
end

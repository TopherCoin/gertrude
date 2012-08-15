#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'uri'
require 'open-uri'
require 'nokogiri'
require 'utils'
require 'mongoconfig'

class TrueKnowledge

    include Cinch::Plugin
    match %r{tk\s+(.+)}, method: :execute

    def initialize(*args)
        super
        @cfg = MongoConfig.new(self)
        @tk_id = @cfg['tk_id'] || raise("can't read tk_id")
        @tk_pw = @cfg['tk_api_key'] || raise("can't read tk_api_key") 
        @tk_url = "http://api.trueknowledge.com/direct_answer?api_account_id=#{@tk_id}&api_password=#{@tk_pw}&structured_response=0&question_entities=0&question="
    end

    def execute(m, target)
        enc = URI.escape(target)
        uri = @tk_url + enc
        doc = Nokogiri::XML(open(uri))
        response = doc.xpath(".//tk:response")[0]['answered']

        if response == 'true'
            txt = doc.xpath(".//tk:text_result")[0].text
            m.reply(txt)
        else
            m.reply("dunno")
        end
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [TrueKnowledge]
        end
    end

    bot.start
end




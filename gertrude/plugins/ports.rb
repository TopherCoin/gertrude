#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'
require 'nokogiri'
require 'scrape'
require 'utils'

# A plugin for performing lookups against IANA assigned port numbers for IP.
# You can search either by number, or by a partial text match against service
# descriptions. 
# Uses the Scraper class to provide persistent cacheing.
class Ports

    # our scraper handler, called when the cache is out of date
    # and we need to rebuild it from scraped web data.
    # Since the IANA services registry is LARGE, we use a SAX style event-driven parser.
    class Handler < Nokogiri::XML::SAX::Document
        def initialize(*args)
            super
            @history = []
        end

        def start_element(name, attributes=[])
            @text = ''
            @history.push name
            case @history.join('/')
                when 'registry/record'
                    @entry = {}
            end
        end

        def characters(string)
            @text += string
        end

        def end_element(name)
            n = @history.join '/'
            case n
            when 'registry/record/protocol'
              @entry['protocol'] = @text.strip.downcase
            when 'registry/record/description'
              @entry['description'] = @text.strip
            when 'registry/record/number'
              @entry['number'] = @text.strip.to_i

            when 'registry/record'
                @collection.insert(@entry)
                @entry = {}
            end
            @history.pop
        end
    end

    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}
    match %r{(udp|tcp)?\s*port\s*(\d+?)}i, method: :lookup_number
    match %r{(udp|tcp)?\s*port\s*([A-Za-z]+?)}i, method: :lookup_name

    def initialize(*args)
        super
        @handler = Handler.new()
        @scraper = Scrape.new(self, db: 'gertrude', collection: 'ports', lifetime: Scrape::MONTHLY, 
                              handler: @handler, drop: true, 
                              url: 'http://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xml')
    end

    def get_data(m)
        @scraper.scrape do
            # block gets executed if we stall the cache
            m.reply("Give me a minute to fetch the data, I'll get back to you")
        end
    end

    def lookup_number(m, protocol, number)
        port = number.to_i
        c = get_data(m)

        if protocol
            if r = c.find_one( { 'protocol' => protocol.downcase, 'number' => port })
                m.reply("%s port %s is %s" % [ Format(:bold, protocol), Format(:bold, number), Format(:italic, r['description'])])
            else
                m.reply("can't find anything for #{protocol} port #{number}")
            end
        else
            cursor = c.find( { 'number' => port} )

            if cursor.count > 0
                cursor.each do |r|
                    description = r['description']
                    description = "(no description)" if description.empty?
                    m.reply("%s port %s is %s" % [ Format(:bold, r['protocol']), Format(:bold, number), Format(:italic, description)])
                end
            else
                m.reply("can't find anything for port #{number}")
            end
        end
    end

    def lookup_name(m, protocol, name)
        c = get_data(m)

        if protocol
            cursor = c.find({ 'protocol' => protocol.downcase, 'description' => %r{#{name}}i})
        else
            cursor = c.find({ 'description' => %r{#{name}}i})
        end

        if cursor
            if cursor.count < 6
                cursor.each do |r|
                    description = r['description']
                    description = "(no description)" if description.empty?
                    m.reply("%s/%s is %s" % [ Format(:bold, r['protocol']), Format(:bold, r['number'].to_s), Format(:italic, description)])
                end
            else
                candidates = []
                cursor.each do |r|
                    candidates << "%s/%s" % [ Format(:bold, r['protocol']), Format(:bold, r['number'].to_s) ]
                end
                m.reply("'#{name}' is maybe #{candidates.join(', ')}")
            end
        else
            m.reply("can't find anything matching '#{name}'")
        end
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Ports]
        end
    end

    bot.start
end



#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'
require 'nokogiri'
require 'scrape'
require 'utils'

# A plugin for performing lookups against IETF RFC, STD, BCP, and FYI documents.
# You can search either by number, or by a partial text match against document
# titles. 
# Uses the Scraper class to provide persistent cacheing.
class RFC

    # our scraper handler, called when the cache is out of date
    # and we need to rebuild it from scraped web data.
    # Since the RFC index is LARGE, we use a SAX style event-driven parser.
    class Handler < Nokogiri::XML::SAX::Document
        def initialize(*args)
            super
            @history = []
        end

        def rfcid(s); s[3..-1].to_i; end

        def start_element(name, attributes=[])
            @text = ''
            @history.push name
            case @history.join('/')
                when 'rfc-index/rfc-entry', 'rfc-index/bcp-entry', 'rfc-index/fyi-entry', 'rfc-index/std-entry'
                    puts "CREATE NEW ENTRY"
                    @entry = {}
            end
        end

        def characters(string)
            @text += string
        end

        def end_element(name)
            n = @history.join '/'
            case n
            when 'rfc-index/rfc-entry/doc-id'
                @entry['rfcid'] = rfcid(@text.strip)
            when 'rfc-index/rfc-entry/title'
                @entry['title'] = @text.strip
            when 'rfc-index/rfc-entry/author/name'
                (@entry['author'] ||= []) << @text.strip
            when 'rfc-index/rfc-entry/obsoletes'
                (@entry['obsoletes'] ||= []) << rfcid(@text.strip)
            when 'rfc-index/rfc-entry/obsoleted-by'
                (@entry['obsoletedby'] ||= []) << rfcid(@text.strip)
            when 'rfc-index/rfc-entry/updated-by'
                (@entry['updatedby'] ||= []) << rfcid(@text.strip)

            when 'rfc-index/bcp-entry/doc-id'
                puts "BCP entry"
                @entry['bcpid'] = rfcid(@text.strip)
            when 'rfc-index/bcp-entry/title'
                @entry['title'] = @text
            when 'rfc-index/bcp-entry/is-also/doc-id'
                (@entry['alias'] ||= []) << rfcid(@text.strip)

            when 'rfc-index/fyi-entry/doc-id'
                @entry['fyiid'] = rfcid(@text.strip)
            when 'rfc-index/fyi-entry/title'
                @entry['title'] = @text.strip
            when 'rfc-index/fyi-entry/is-also/doc-id'
                (@entry['alias'] ||= []) << rfcid(@text.strip)

            when 'rfc-index/std-entry/doc-id'
                @entry['stdid'] = rfcid(@text.strip)
            when 'rfc-index/std-entry/title'
                @entry['title'] = @text.strip
            when 'rfc-index/std-entry/is-also/doc-id'
                (@entry['alias'] ||= []) << rfcid(@text.strip)

            when 'rfc-index/rfc-entry', 'rfc-index/bcp-entry', 'rfc-index/fyi-entry', 'rfc-index/std-entry'
                @collection.insert(@entry)
                @entry = {}
            end
            @history.pop
        end

        def end_document
        end
    end

    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}
    match %r{rfc\s*(\d+)}, method: :rfc_numeric
    match %r{rfc\s+(\S+)}, method: :stringy
    match %r{bcp\s*(\d+)}, method: :bcp_numeric
    match %r{fyi\s*(\d+)}, method: :fyi_numeric
    match %r{std\s*(\d+)}, method: :std_numeric

    def initialize(*args)
        super
        @handler = Handler.new()
        @scraper = Scrape.new(self, db: 'gertrude', collection: 'rfc', lifetime: Scrape::MONTHLY, 
                              handler: @handler, drop: true, 
                              url: 'http://www.ietf.org/rfc/rfc-index.xml')
    end

    def get_data(m)
        @scraper.scrape do
            # block gets executed if we stall the cache
            m.reply("Give me a minute to fetch the data, I'll get back to you")
        end
    end

    def rfc_numeric(m, target)
        c = get_data(m)
        r = c.find_one( { 'rfcid' => target.to_i })

        reply = "no RFCs match"

        if r
            reply = Format(:bold, "RFC#{r['rfcid']}")
            reply << Format(:italic, " '#{r['title']}'")
            reply << " " + r['author'].join(', ')

            if r['obsoletes'] && !r['obsoletes'].empty?
                reply << Format(:green, " [obsoletes #{r['obsoletes'].join(',')}]")
            end

            if r['obsoletedby'] && !r['obsoletedby'].empty?
                reply << Format(:red, " [obsoleted by #{r['obsoletedby'].join(',')}]")
            end

            if r['updatedby'] && !r['updatedby'].empty?
                reply << Format(:orange, "[updated by #{r['updatedby'].join(',')}]")
            end
        end

        # TODO: find BCPs etc that also match

        m.reply(reply)
    end

    def bcp_numeric(m, target)
        c = get_data(m)
        r = c.find_one( { 'bcpid' => target.to_i } )

        reply = "no BCPs match"

        if r
            rfcs = r['alias'].map{|a| "RFC#{a}"}.join ', '
            reply = Format(:bold, "BCP#{r['bcpid']}") + " aka #{rfcs}"
        end

        m.reply(reply)
    end

    def fyi_numeric(m, target)
        c = get_data(m)
        r = c.find_one( { 'fyiid' => target.to_i } )

        reply = "no FYIs match"

        if r
            rfcs = r['alias'].map{|a| "RFC#{a}"}.join ', '
            reply = Format(:bold, "FYI#{r['fyiid']}") + " aka #{rfcs}"
        end

        m.reply(reply)
    end

    def std_numeric(m, target)
        c = get_data(m)
        r = c.find_one( { 'stdid' => target.to_i } )

        reply = "no STDs match"

        if r
            rfcs = r['alias'].map{|a| "RFC#{a}"}.join ', '
            reply = Format(:bold, "STD#{r['stdid']}")
            reply << Format(:italic, " #{r['title']}")
            reply << " aka #{rfcs}"
        end

        m.reply(reply)
    end

    def stringy(m, target)
        c = get_data(m)
        cursor = c.find( { 'title' => %r{#{target}}i } )

        if cursor.count < 6
            cursor.each do |r|
                if r['rfcid']
                    m.reply("%s%s" % [ Format(:bold, "RFC#{r['rfcid']}"), r['title'] ? Format(:italic, " - #{r['title']}") : ""])
                elsif r['bcpid']
                    m.reply("%s%s" % [ Format(:bold, "BCP#{r['bcpid']}"), r['title'] ? Format(:italic, " - #{r['title']}") : ""])
                elsif r['fyiid']
                    m.reply("%s%s" % [ Format(:bold, "FYI#{r['fyiid']}"), r['title'] ? Format(:italic, " - #{r['title']}") : ""])
                elsif r['stdid']
                    m.reply("%s%s" % [ Format(:bold, "STD#{r['stdid']}"), r['title'] ? Format(:italic, " - #{r['title']}") : ""])
                end
            end
        else
            l = []
            cursor.each do |r|
                if r['rfcid']
                    l << "RFC#{r['rfcid']}"
                elsif r['bcpid']
                    l << "BCP#{r['bcpid']}"
                elsif r['fyiid']
                    reply << "FYI#{r['fyiid']}"
                elsif r['stdid']
                    l << "STD#{r['stdid']}"
                end
            end
            m.reply("Possible matches: #{l.join(', ')}")
        end
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [RFC]
        end
    end

    bot.start
end


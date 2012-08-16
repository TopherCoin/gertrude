#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'
require 'nokogiri'
require 'scrape'
require 'utils'

# A plugin for performing lookups against IEEE Organisational Unique Identifiers.
# You can search either by number, or by a partial text match against service
# descriptions. 
# Uses the Scraper class to provide persistent cacheing.
class OUI

    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}
    match %r{(?:mac|oui)\s+([0-9a-fA-F]{2,2})[-:, ]([0-9a-fA-F]{2,2})[-:, ]([0-9a-fA-F]{2,2})}i, method: :lookup_number
    match %r{(?:mac|oui)\s+([A-Za-z]+?)}i, method: :lookup_name

    def initialize(*args)
        super
        @scraper = Scrape.new(self, db: 'gertrude', collection: 'ouis', lifetime: Scrape::MONTHLY, 
                              drop: true, 
                              url: 'http://standards.ieee.org/develop/regauth/oui/oui.txt') do |c,s|
            s.each_line do |l|
                if p = l.match(%r{^([0-9A-F]{2,2})-([0-9A-F]{2,2})-([0-9A-F]{2,2})\s+\(hex\)\s+(.*)$}) 
                    @entry = { 'oui' => ("%s%s%s" % [p[1], p[2], p[3]]), 'company' => p[4] }
                    c.insert(@entry)
                end
            end
        end
    end

    def get_data(m)
        @scraper.scrape do
            # block gets executed if we stall the cache
            m.reply("Give me a minute to fetch the data, I'll get back to you")
        end
    end

    def lookup_number(m, hi, mid, lo)
        oui = "%s%s%s" % [hi.upcase, mid.upcase, lo.upcase]
        c = get_data(m)

        if r = c.find_one( { 'oui' => oui })
            m.reply("%s is registered to %s" % [ Format(:bold, "%s:%s:%s" % [hi, mid, lo]), Format(:italic, r['company'])])
        else
            m.reply("can't find anything for %s:%s:%s" % [hi, mid, lo])
        end
    end

    def lookup_name(m, name)
        c = get_data(m)

        cursor = c.find({ 'company' => %r{#{name}}i})

        if cursor
            candidates = []
            cursor.each do |r|
                candidates << Format(:bold, r['oui'])
            end
            m.reply("'#{name}' is maybe #{candidates.join(', ')}")
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
            c.plugins.plugins = [OUI]
        end
    end

    bot.start
end




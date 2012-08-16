#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'open-uri'
require 'csv'

require 'scrape'
require 'utils'

# plugin for looking up TAC (Type Allocation Code) numbers - the first 8 digits
# of a GSM device's IMEI number.
class TAC
    include Cinch::Plugin

    LOOKUP = 'http://www.mulliner.org/tacdb/feed/tac-new_cleanup.csv'

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}
    match %r{(?:tac|imei)\s+(\d{8,8})}, method: :tac
    match %r{(?:tac|imei)\s+(\S+)\s*(\S*)}, method: :mfmodel

    def initialize(*args)
        super
        @scraper = Scrape.new(self, db: 'gertrude', collection: 'tacs', lifetime: Scrape::MONTHLY, 
                              drop: true, 
                              url: LOOKUP) do |c,s|
            s.each_line do |l|
                p = CSV.parse_line(l)
                p[1] ||= 'unknown mf'
                p[2] ||= 'unknown model'
                c.insert( { 'tac' => p[0].to_i, 'mf' => p[1].strip, 'model' => p[2].strip })
            end
        end
    end

    def get_data(m)
        @scraper.scrape do
            # block gets executed if we stall the cache
            m.reply("Give me a minute to fetch the data, I'll get back to you")
        end
    end

    def tac(m, tac)
        c = get_data(m)

        if r = c.find_one( { 'tac' => tac.to_i } )
            m.reply("TAC #{tac} is %s %s" % [ Format(:bold, r['mf']), Format(:italic, r['model'])])
        else
            m.reply("No matches for TAC #{tac}")
        end
    end

    def mfmodel(m, mf, model)
        #puts "MFMODEL MF:#{mf} MODEL: #{model}"
        c = get_data(m)

        if mf && model
            cursor = c.find( { 'mf' => %r{#{mf}}i, 'model' => %r{#{model}}i } )
        else
           if mf 
               cursor = c.find( { 'mf' => %r{#{mf}}i } )
           else
               cursor = c.find( { 'model' => %r{#{model}}i } )
           end
        end

        if cursor && (cursor.count > 0)
            if cursor.count < 6
                cursor.each do |r|
                    m.reply("TAC%s %s %s" % [ r['tac'].to_s, Format(:bold, r['mf']), Format(:italic, r['model']) ])
                end
            else
                candidates = []
                cursor.each do |r|
                    candidates << r['tac']
                end

                if candidates.length > 30
                    m.reply("Too many matches to list, first few are: #{candidates[0..29].join(', ')}")
                else
                    m.reply("Possible matches: #{candidates.join(', ')}")
                end
            end
        else
            m.reply("No matches for #{mf} #{model}")
        end
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [TAC]
        end
    end

    bot.start
end





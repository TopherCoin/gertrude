#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'
require 'nokogiri'
require 'json'
require 'scrape'
require 'utils'
require 'mongoconfig'

# a plugin for converting currency, based on the exchange rate API
# of openexchangerates.org, which updates every hour and allows 1000
# queries per month on a free account, so we set our refresh rate just
# below that,
class Currency
    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}
    match %r{(?:convert|change)\s*([0-9.]+)\s+(\S+)\s+(?:to\s+)?([^?]+)}, method: :convert
    match %r{currency(?:\s+for)?\s+([^?]+)}, method: :currency

    def initialize(*args)
        super
        @cfg = MongoConfig.new(self)
        @api_key = @cfg['api_key'] || raise("can't read API key")
        @latest_url = "http://openexchangerates.org/api/latest.json?app_id=#{@api_key}"
        @symbols_url = "http://openexchangerates.org/api/currencies.json"

        @currency_scraper = Scrape.new(self, db: 'gertrude', collection: 'currencies', 
                                       lifetime: Scrape::MONTHLY, 
                                        drop: true, 
                                        url: @symbols_url) do |c,s|
            h = JSON.parse(s.read)
            h.each_pair do |k,v|
                c.insert( { symbol: k.upcase, description: v } )
            end
        end

        @rate_scraper = Scrape.new(self, db: 'gertrude', collection: 'exchange_rates', 
                                       lifetime: Scrape::HOURLY, 
                                        drop: true, 
                                        url: @latest_url) do |c,s|
            h = JSON.parse(s.read)
            h['rates'].each_pair do |k,v|
                c.insert( { symbol: k.upcase, dollar: v.to_f } )
            end
        end


    end

    def get_currencies(m)
        @currency_scraper.scrape do
            # block gets executed if we stall the cache
            m.reply("Give me a minute to fetch the currency symbols, I'll get back to you")
        end
    end

    def get_rates(m)
        @rate_scraper.scrape do
            # block gets executed if we stall the cache
            m.reply("Just a sec while I fetch the latest exchange rates...")
        end
    end

    def convert(m, amount, src, dst)
        c = get_currencies(m)
        r = get_rates(m)

        if t_src = c.find_one({ symbol: src.upcase})
            if t_dst = c.find_one( { symbol: dst.upcase})
                if r_src = r.find_one( { symbol: src.upcase })
                    if r_dst = r.find_one( { symbol: dst.upcase })
                        rate = r_dst['dollar'] / r_src['dollar']
                        amount2 = amount.to_f * rate
                        puts "r_src: #{r_src['dollar']} r_dst #{r_dst['dollar']} rate #{rate} amount2 #{amount2}"
                        reply = "%.2d %s (%s) makes %.2d %s (%s)" % [ amount, 
                                                                      Format(:bold, src), 
                                                                      Format(:italic, t_src['description']),
                                                                      amount2,
                                                                      Format(:bold, dst),
                                                                      Format(:italic, t_dst['description']) ]
                        m.reply(reply)
                    else
                        m.reply("can't find a rate for #{dst}")
                    end
                else
                    m.reply("can't find a rate for #{src}")
                end
            else
                m.reply("can't find any currency called '#{dst}'")
            end
        else
            m.reply("can't find any currency called '#{src}'")
        end
    end

    def currency(m, target)
        c = get_currencies(m)
        cursor = c.find( { 'description' => %r{#{target}}i } )

        if cursor.count < 6
            candidates = []
            cursor.each do |r|
                candidates << "%s (%s)" % [ Format(:bold, r['symbol']), Format(:italic, r['description']) ]
            end
            m.reply("'#{target}' could be #{candidates.join(', ')}")
        else
            candidates = []
            cursor.each do |r|
                candidates << "%s" % [ Format(:bold, r['symbol']) ]
            end
            m.reply("'#{target}' is maybe #{candidates.join(', ')}")
        end
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Currency]
        end
    end

    bot.start
end



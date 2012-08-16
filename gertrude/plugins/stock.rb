#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'open-uri'
require 'csv'
require 'utils'

# plugin for doing stock exchange lookups, using Yahoo's finance API.
class Stock
    include Cinch::Plugin

    QUOTE = 'http://quote.yahoo.com/d/quotes.csv?f=sl1d1t1c1ohgv&e=.csv&s='
    LOOKUP = 'http://finance.yahoo.com/l?t=S&s='

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}
    match %r{(?:stock|shares)\s+([^?]+)}, method: :price
    match %r{company\s+([^?]+)}, method: :ticker

    def initialize(*args)
        super
        @markets = [ 'London', 'LON', 'LSE', 'NasdaqMM', 'NASDAQ', 'NYSE', 'NMS', 'AMEX', 'NSE', 'Paris', 'PAR']
    end

    def price(m, target)
        uri = QUOTE + target
        f = open(uri)

        if f
            # symbol, price, date, time, change, open, high, low, volume
            stock_values = CSV.parse_line(f.read)

            if stock_values[2] =~ /N\/A/
                m.reply("can't find the stock symbol '#{target}'")
            else # symbol matched
                change = stock_values[4].to_f

                if change != 0
                    if change > 0
                        change_str = "%s %.2f" % [Format(:green, 'up'), change]
                    else
                        change_str = "%s %.2f" % [Format(:red, 'down'), 0.0 - change]
                    end
                else
                    change_str = "no change"
                end

                symbol = Format(:bold, stock_values[0])
                price = Format(:blue, stock_values[1])
                low = stock_values[7]
                high = stock_values[6]
                open = stock_values[5]
                volume = stock_values[8].reverse.scan(/\d{1,3}/).join(',').reverse
                message = "%s: %s %s (lo: %s hi: %s) open: %s vol: %s" % [ symbol, price, change_str, low, high, open, volume ]
                m.reply(message)
            end
        else
            m.reply("sorry, can't get stock data temporarily")
        end
    end

    def ticker(m, target)
        uri = LOOKUP + target
        f = open(uri)

        if f
            symbols = []
            rows = f.read.scan(/<tr\s+class="yui-dt-(?:even|odd)">.*?<\/tr>/)
            puts "ROWS: " + rows.join("\n")
            rows.each do |r|
                cols = r.scan(/<td.*?<\/td>/)
                puts "COLS: " + cols.join("\n")
                # symbol, name, last trade, type, category, exchange
                symbol = cols[0].match(/\?s=(.*?)"/)[1]

                name = cols[1].match(/<td>(.*?)<\/td>/)[1]
                exchange = cols[5].match(/<td>(.*?)<\/td>/)[1]
                puts "SYMBOL: %s  NAME: %s  EXCHANGE: %s" % [symbol, name, exchange]

                # if the company's name matches the search string, and its market is
                # one of our configured markets, include it as a candidate
                name_regex = Regexp.new(target, Regexp::IGNORECASE)
                exchange_regex = Regexp.new(exchange, Regexp::IGNORECASE)

                if name.match(name_regex)
                    @markets.each do |m|
                        r = Regexp.new(m, Regexp::IGNORECASE)
                        if exchange.match(r)
                            symbols.push([symbol, name])
                            break
                        end
                    end
                end
            end

            # symbols is now candidate list [[sym,name]....]
            unless symbols.empty?
                candidates = symbols.collect {|x| "%s (%s)" % [ Format(:bold, x[0]), x[1] ] }
                message = candidates.join(", ") 
                m.reply(message)
            else
                m.reply("sorry, can't find any matches")
            end
        else
            m.reply("sorry, can't get company data temporarily")
        end
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Stock]
        end
    end

    bot.start
end




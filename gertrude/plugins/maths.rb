#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)

# cinch stuff
require 'cinch'

# gertrude stuff
require 'number_parser'
require 'exec'

class Maths
    include Cinch::Plugin

    match /.+/, suffix: /\?\?$/, use_prefix: false, react_on: :channel, method: :channel_msg
    match /.+/, suffix: /\?$/, method: :private_msg

    # allow other plugins to set the value of @ans
    listen_to :calculation_result, method: :set_ans

    def initialize(*args)
        super
        @parser = NumberParser.new
        @sandbox = BlankSlate.new
    end

    def set_ans(m, x)
        @sandbox.ans = x
    end

    def channel_msg(m)
        s = m.message.gsub(/\?+$/, '')
        if result = process_msg(s)
            m.reply(result, true)
        end
    end

    def private_msg(m)
        s = m.message.gsub(/\?+$/, '')
        if result = process_msg(s)
            m.reply(result, true)
        end
    end

    def process_msg(m)
        result = nil

        # convert verbose numerics to integers
        if @parser.is_candidate?(m)
            a = @parser.parse(m)
            m = a.join(' ')
        end

        # handle exponentiation
        m.gsub!(/ to the power of /, " ** ")
        m.gsub!(/ to the /, " ** ")

        # handle multiplication, division, addition, subtraction, power, percent
        m.gsub!(/\btimes\b/, "*")
        m.gsub!(/\bdiv(ided by)? /, "/ ")
        m.gsub!(/\bover /, "/ ")
        m.gsub!(/\bsquared/, "**2 ")
        m.gsub!(/\bcubed/, "**3 ")
        m.gsub!(/\bto\s+(\d+)(r?st|nd|rd|th)?( power)?/, '**\1 ')
        m.gsub!(/\bpercent of/, "*0.01*")
        m.gsub!(/\bpercent/, "*0.01")
        m.gsub!(/\% of\b/, "*0.01*")
        m.gsub!(/\%/, "*0.01")
        m.gsub!(/\+VAT/i, "*1.2")
        m.gsub!(/\-VAT/i, "/1.2")
        m.gsub!(/\bsquare root of (\d+(\.\d+)?)/, '\1 ** 0.5 ')
        m.gsub!(/\bcubed? root of (\d+(\.\d+)?)/, '\1 **(1.0/3.0) ')
        m.gsub!(/ of /, " * ")
        m.gsub!(/(plus|and)/, "+")
        m.gsub!(/(minus|less)/, "-")

        # ruby doesn't like floating-point values without a 0
        # in front of them, so find any non-digit followed by
        # a .<digits> and insert a 0 before the .
        m.gsub!(/(\D|^)(\.\d+)/,'\10\2')

        # execute the expression, if we get a result reply with it
        begin
            result = @sandbox.exec(m)
        rescue BlankSlate::Timeout => e
            # took too long - poss. malicious while loop
        rescue SecurityError => e
            # an attempt to do something fruity 
        rescue Exception => e
            # trying to access system() etc, or honest expression error
        end
        
        # tidy the result format
        if result =~ /^[-+\de\.]+$/
            result = sprintf("%1.12f", result)
            result.gsub!(/\.?0+$/, "")
            result.gsub!(/(\.\d+)000\d+/, '\1')
        end
        if (result.to_s.length > 30)
            result = "a number with #{result.to_s.length} digits..."
        end
        result
    end
end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Maths]
        end
    end

    bot.start
end


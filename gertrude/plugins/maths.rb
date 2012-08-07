#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)

# cinch stuff
require 'cinch'

# gertrude stuff
require 'english'
require 'exec'

class Maths
    include Cinch::Plugin

    match /.+/, suffix: /\?\?$/, use_prefix: false, react_on: :channel, method: :channel_msg
    match /.+/, suffix: /\?$/, method: :private_msg

    def initialize(*args)
        super
        @parser = NumberParser.new
        @sandbox = BlankSlate.new

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
        if @parser.candidate?(m)
            m = @parser.replace(m)
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
        m.gsub!(/\bsquare root of (\d+(\.\d+)?)/, '\1 ** 0.5 ')
        m.gsub!(/\bcubed? root of (\d+(\.\d+)?)/, '\1 **(1.0/3.0) ')
        m.gsub!(/ of /, " * ")
        m.gsub!(/(plus|and)/, "+")
        m.gsub!(/(minus|less)/, "-")

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
        result
    end
end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#ukha"]
            c.plugins.plugins = [Maths]
        end
    end

    bot.start
end


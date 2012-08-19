#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'


class PartyLineTestA
    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}

    match %r{what\s+is\s+(\S+)}, react_on: :message, method: :what

    def what(m, x)
        if ret = [true, false].sample
            m.reply("#{self.class} has no idea what #{x} is")
        end
        ret
    end
end






class PartyLineTestB
    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}

    match %r{what\s+is\s+(\S+)}, react_on: :message, method: :what

    def what(m, x)
        if ret = [true, false].sample
            m.reply("#{self.class} has no idea what #{x} is either")
        end
        ret
    end
end







class PartyLineTestC
    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}

    match %r{what\s+is\s+(\S+)}, react_on: :message, method: :what

    def what(m, x)
        if ret = [true, false].sample
            m.reply("finally, #{self.class} has zero clue about #{x}")
        end
        ret
    end
end

# Illustrates that PartyLineTest[ABC] are all proper plugin citizens, they can
# be executed directly as cinch plugins without using the PartyLine proxy.
if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [PartyLineTestA, PartyLineTestB, PartyLineTestC]
        end
    end

    bot.start
end


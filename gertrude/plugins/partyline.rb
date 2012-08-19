#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require './partyline_test'

require 'delegate'

# The PartyLine plugin acts as a proxy for other plugins; you can register
# plugins with an instance of PartyLine exactly as you would with an instance
# of Bot.
# The crucial difference is that plugins registered with PartyLine have their
# handlers called sequentially, rather than in parallel. If any handler returns
# a TRUE value, the remaining candidate handlers are not called.
#
# This allows the same event to be handled by multiple plugins, on a 
# first-come-first-served basis.
#
# For example, imagine there are three plugins which can respond to the channel
# message "what is X?" where X is some string. PluginA does a simple lookup of X in
# a hash in RAM, PluginB looks up X in a local database, and PluginC sends the string
# X via HTTP to some remote lookup service. PartyLine allows us to try PluginA, then
# if it can't handle the request try PluginB. And if that can't deal with it either
# we finally resort to PluginC. In this way, we don't attempt the more computationally
# expensive solutions until we have exhausted the simpler possibilities.
#
# With a vanilla cinch bot/plugin approach, all three plugins would execute in parallel.
# Also, if they all had a match for X, you'd get three responses, which is quite confusing.

# Plugins want to register themselves with bot.handlers, but PartyLine wants to manage
# its own independent set of plugins. The BotDelegate delegates all methods to @bot,
# with the exception of the @handlers attribute, and the @plugins attribute.

# WITHOUT PartyLine (PartyLineTestA, PartyLineTestB, PartyLineTestC all regular cinch plugins):
#
# [16:01] <blowbacH> gertrude, what is cheese
# [16:01] <gertrude> PartyLineTestB has no idea what cheese is either
# [16:01] <gertrude> finally, PartyLineTestC has zero clue about cheese
# [16:01] <gertrude> PartyLineTestA has no idea what cheese is

# WITH PartyLine (PartyLineTest[ABC] are subordinate plugins)
#
# [16:20] <blowbacH> gertrude, what is cheese
# [16:20] <gertrude> PartyLineTestB has no idea what cheese is either
# [16:20] <blowbacH> gertrude, what is cheese
# [16:20] <gertrude> PartyLineTestA has no idea what cheese is
# [16:20] <blowbacH> gertrude, what is cheese
# [16:20] <gertrude> PartyLineTestB has no idea what cheese is either
# [16:20] <blowbacH> gertrude, what is cheese
# [16:20] <gertrude> PartyLineTestA has no idea what cheese is
# [16:20] <blowbacH> gertrude, what is cheese
# [16:20] <gertrude> finally, PartyLineTestC has zero clue about cheese

class BotDelegate < Delegator
    attr_accessor :handlers
    attr_reader :plugins

    def initialize(bot)
        super 
        @bot = bot
        @plugins  = Cinch::PluginList.new(self) # manage our own plugins
        @handlers = Cinch::HandlerList.new      # manage our own handler list
        @handlers.synchronous = true     # our handlers are SYNCHRONOUS
    end

    def __getobj__; @bot; end
    def __setobj__(bot); @bot = bot; end
end

class PartyLine

    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}

    match %r{what\s+is\s+(\S+)}, react_on: :message, method: :what

    def initialize(*args)
        super
        @bot_delegate = BotDelegate.new(@bot)

        @bot_delegate.plugins.register_plugins( [ PartyLineTestA, PartyLineTestB, PartyLineTestC ] )
    end

    def what(m, x)
        # unfortunately, plugins don't know what the event list is for a
        # given invocation, so we're hardwiring all our child plugins to 
        # respond to :message here
        @bot_delegate.handlers.dispatch(:message, m, x)
    end

end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [PartyLine]
        end
    end

    bot.start
end





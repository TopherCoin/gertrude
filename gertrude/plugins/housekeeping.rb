#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'auth'
require 'utils'

# various housekeeping tasks to do with joining, parting, inviting etc.
# most of these housekeeping operations require bot-operator privileges - 
# authentication is handled by the auth module.
class Housekeeping

    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    #set :suffix, %r{\??\Z}

    # only allow authentication by privmsg
    match %r{auth\s+(\S+)\s+(\S+)\s+(\S+)}, react_on: :privmsg, method: :auth

    # watch for users leaving so we can clear their sessions
    listen_to :offline, method: :offline
    
    match %r{join\s+(#\S+)}, method: :join
    match %r{part\s+(#\S+)}, method: :part
    match %r{invite\s+(\S+)\s+(?:to\s+)?(#\S+)}, method: :invite
    match %r{do\s+(\S+)\s+(.*)}, method: :action
    match %r{say\s+(\S+)\s+(.*)}, method: :say
    match %r{botsnack}, method: :botsnack
    match %r{quit}, method: :quit

    def initialize(*args)
        super
        @authenticator = Authenticator.instance()
    end

    def auth(m, username, password, otp)
        mask = m.user.mask("%u@%h")
        
        if @authenticator.authenticate(mask, username, password, otp)
            m.user.monitor
            m.reply("authenticated")
        else
            @authenticator.unauthenticate(mask) 
            m.user.unmonitor
            m.reply("authentication failed")
        end
    end

    def offline(m, user)
        mask = m.user.mask("%u@%h")
        @authenticator.unauthenticate(mask) 
        m.user.unmonitor
    end

    def is_authed?(m)
        mask = m.user.mask("%u@%h")
        if @authenticator.authenticated?(mask)
            return true
        end
        m.reply("Please authenticate via %s : %s" % [ Format(:red, "PRIVMSG"), Format(:bold, "!auth username password OTP") ])
        false
    end

    def join(m, channel)
        Channel(channel).join if is_authed?(m)
    end

    def part(m, channel)
        Channel(channel).part if is_authed?(m)
    end

    def invite(m, nick, channel)
        Channel(channel).invite(nick) if is_authed?(m)
    end

    def action(m, target, action)
        puts "TARGET #{target} ACTION: '#{action}'"
        Target(target).action(action) if is_authed?(m)
    end

    def say(m, target, utterance)
        puts "TARGET #{target} UTTERANCE: '#{utterance}'"
        Target(target).send(utterance) if is_authed?(m)
    end

    def botsnack(m)
        m.reply(["Thanks!", "Yum!", "Tasty!", "Mmmm ;)", "Ta!"].sample)
    end

    def quit(m)
        bot.quit("Guru Meditation #00000004.0000AAC0") if is_authed?(m)
    end


end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Housekeeping]
        end
    end

    bot.start
end



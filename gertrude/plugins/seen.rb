#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'
require 'utils'

class Seen

  include Cinch::Plugin
  listen_to :channel, :leaving, :join, :topic, :nick, method: :listen
  match %r{seen\s+(\S+)}, method: :execute

  def initialize(*args)
    super
    @db = Mongo::Connection::new.db("gertrude")
    @coll = @db.collection("seen")
  end

  def listen(m,*args)
      # don't need to listen to :action, we get than as part of :channel
      n = m.user.nick
      nc = n.downcase # canonical
      ln = m.user.last_nick
      lnc = ln.downcase
      c = m.channel ? m.channel.name : "none"

      if m.events.include?(:topic) # :catchall :topic
          @coll.update({nick: nc}, { nick: nc, user: n, timestamp: Time.now.to_i, channel: c, action: 'TOPIC', info: m.params.last}, {upsert: true})
      elsif m.events.include?(:join) # :catchall :topic
          @coll.update({nick: nc}, { nick: nc, user: n, timestamp: Time.now.to_i, channel: c, action: 'JOIN', info: c}, {upsert: true})
      elsif m.events.include?(:leaving) # :catchall :leaving :part
          @coll.update({nick: nc}, { nick: nc, user:n, timestamp: Time.now.to_i, channel: c, action: 'PART', info: c}, {upsert: true})
      elsif m.events.include?(:nick) # :catchall :nick
          @coll.update({nick: lnc}, { nick: lnc, user:ln, timestamp: Time.now.to_i, channel: c, action: 'NICK', info: n}, {upsert: true})
      elsif m.events.include?(:channel)
          if m.events.include?(:action) # :catchall :ctcp :channel :message :action :privmsg
              @coll.update({nick: nc}, { nick: nc, user: ln, timestamp: Time.now.to_i, channel: c, action: 'ACTION', info: m.action_message}, {upsert: true})
          else
              @coll.update({nick: nc}, { nick: nc, user: ln, timestamp: Time.now.to_i, channel: c, action: 'PUBLIC', info: m.message}, {upsert: true})
          end
      end
  end

  def execute(m, target)
      if target == @bot.nick
          m.reply "That's me!"
      elsif target == m.user.nick
          m.reply "That's you!"
      elsif i = @coll.find_one({nick: target.downcase})
          # the 'nick' field is stored in a canonical lower case form; however as of this incarnation
          # we store the original caseful form in 'user' for maximum splendour
          if i['user']
            ret = "#{i['user']} was last seen "
          else
            ret = "#{target} was last seen "
          end

          ago = Time.new.to_i - i['timestamp']

          if(ago.to_i < 10)
              ret << "just now, "
          else
              ret << Utils.secs_to_string(ago) + " ago, "
          end

          ret << case i['action']
          when 'PUBLIC'
              "saying #{i['info']}"
          when 'ACTION'
              "doing #{i['nick']} #{i['info']}"
          when 'NICK'
              "changing nick from #{i['nick']} to #{i['info']}"
          when 'PART'
              "leaving #{i['channel']}"
          when 'JOIN'
              "joining #{i['channel']}"
          when 'TOPIC'
              "changing the topic of #{i['channel']} to #{i['info']}"
          when 'QUIT'
              "quitting IRC (#{i['info']})"
          end
          m.reply(ret)
      else
          m.reply("I haven't seen #{target}")
      end
  end

end


if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Seen]
        end
    end

    bot.start
end



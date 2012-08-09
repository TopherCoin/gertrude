#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'

class Seen

  include Cinch::Plugin
  listen_to :channel, :leaving, :join, :topic, :nick, method: :listen

  def initialize(*args)
    super
    @users = {}
    @db = Mongo::Connection::new.db("gertrude")
    @coll = @db.collection("seen")
  end

  def listen(m,*args)
    #@users[m.user.nick] = SeenStruct.new(m.user, m.channel, m.message, Time.now)
    #@db["seen"].insert({ nick: m.user, 
      # don't need to listen to :action, we get than as part of :channel
      if m.events.include?(:topic) # :catchall :topic
          @coll.update({nick: m.user.nick}, { nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'TOPIC', info: m.params.last}, {upsert: true})
          #m.reply ({ nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'TOPIC', info: m.params.last})
      elsif m.events.include?(:join) # :catchall :topic
          @coll.update({nick: m.user.nick}, { nick: m.user.nick, time: Time.now.to_i, channel: m.channel, action: 'JOIN', info: m.channel}, {upsert: true})
          #m.reply ({ nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'JOIN', info: m.channel.name})
      elsif m.events.include?(:leaving) # :catchall :leaving :part
          @coll.update({nick: m.user.nick}, { nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'PART', info: m.channel.name}, {upsert: true})
          #m.reply ({ nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'PART', info: m.channel.name})
      elsif m.events.include?(:nick) # :catchall :nick
          @coll.update({nick: m.user.nick}, { nick: m.user.last_nick, time: Time.now.to_i, channel: m.channel.name, action: 'NICK', info: m.user.nick}, {upsert: true})
          #m.reply ({ nick: m.user.last_nick, time: Time.now.to_i, channel: 'none', action: 'NICK', info: m.user.nick})
      elsif m.events.include?(:channel)
          if m.events.include?(:action) # :catchall :ctcp :channel :message :action :privmsg
              @coll.update({nick: m.user.nick}, { nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'ACTION', info: m.action_message}, {upsert: true})
              #m.reply ({ nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'ACTION', info: m.action_message})
          else
              @coll.update({nick: m.user.nick}, { nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'PUBLIC', info: m.message}, {upsert: true})
              #m.reply ({ nick: m.user.nick, time: Time.now.to_i, channel: m.channel.name, action: 'PUBLIC', info: m.message})
          end
      end
      #m.reply("#{m.events} #{args} #{m}")
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



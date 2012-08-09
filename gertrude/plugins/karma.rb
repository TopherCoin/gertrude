#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongo'
require 'utils'

class Karma

  include Cinch::Plugin
  listen_to :channel, method: :listen
  match %r{karma\s+(?:for\s+)?(\S+)}, method: :execute
  match %r{karmastats}, method: :execute_stats

  def initialize(*args)
    super
    @users = {}
    @db = Mongo::Connection::new.db("gertrude")
    @coll = @db.collection("karma")
  end

  def listen(m, *args)
      # don't need to listen to :action, we get than as part of :channel
      n = m.user.nick
      nc = n.downcase # canonical

      unless n == @bot.nick # don't listen to ourself
          if m.events.include?(:message)
              op = nil

              if m.message.match(%r{\+\+|\-\-})
                  t = m.message.gsub(%r{\?+$}, '')
                  if mm = t.match(%r{--([^-+]+.*)$}) || t.match(%r{([^-+]+.*)--\s*$})
                      op = -1
                      arg = mm[1]
                  elsif mm = t.match(%r{\+\+([^-+]+.*)$}) || t.match(%r{([^-+]+.*)\+\+\s*$})
                      op = 1
                      arg = mm[1]
                  else
                      #m.reply("eh?")
                  end

                  if op
                      if arg == m.user.nick
                          m.reply("It is unseemly to karma oneself")
                      else
                          @coll.update({subject: arg}, {subject: arg, "$inc" => { karma: op }}, {upsert: true})

                          if arg == m.bot.nick
                              if op == 1
                                  m.reply("Thanks!")
                              else
                                  m.reply("Bah :(")
                              end
                          end
                      end
                  end
              end
          end
      end
  end

  def execute(m, target)
      # look for a single, exact match
      if k = @coll.find_one({subject: target}) 
          m.reply("karma for '#{target}' is #{k['karma']}")
      # look for a few partial matches
      elsif k = @coll.find({ subject: %r{#{target}} }, { limit: 5, sort: ['karma', Mongo::DESCENDING] }).to_a 
          replies = k.inject([]) do |acc, n|
              acc.push "#{n['subject']}:#{n['karma']}"
          end
          m.reply(replies.join(', '))
      end

      if k.nil? || k.empty?
          m.reply("'#{target}' has neutral karma")
      end
  end

  def execute_stats(m)
      if t = @coll.find( {}, { limit: 5, sort: [ 'karma', Mongo::DESCENDING ] } ).to_a
          replies = t.inject([]) do |acc, n|
              acc.push "#{n['subject']}:#{n['karma']}"
          end
          m.reply("top: #{replies.join(', ')}")
      end

      if b = @coll.find( {}, { limit: 5, sort: [ 'karma', Mongo::ASCENDING  ] } ).to_a
          replies = b.inject([]) do |acc, n|
              acc.push "#{n['subject']}:#{n['karma']}"
          end
          m.reply("btm: #{replies.reverse.join(', ')}")
      end
  end
            
end


if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Karma]
        end
    end

    bot.start
end




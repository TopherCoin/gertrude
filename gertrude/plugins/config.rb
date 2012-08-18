#!/usr/bin/env ruby

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)
require 'cinch'

require 'mongoconfig'
require 'auth'
require 'exec'
require 'utils'

# manipulate per-plugin configuration data, as stored by the MongoConfig class.
# config manipulation requires authentication, it is assumed that this is handled
# by the Auth plugin.
class Configs

    include Cinch::Plugin

    set :prefix, %r{\A(?:!|gertrude,\s*)}
    set :suffix, %r{\??\Z}

    
    match %r{config\s+(?:show|list|ls|all)\s*(\S+?)?}, method: :show_config
    match %r{config\s+drop\s+(\S+?)}, method: :drop_config
    match %r{config\s+(?:rm|delete|del)\s+(\S+?)}, method: :del_config

    match %r{config\s+get\s+(\S+?)}, method: :get_config
    match %r{config\s+set\s+(\S+)\s*=\s*(.*?)}, method: :set_config

    def initialize(*args)
        super
        @authenticator = Authenticator.instance()
        @cfg = MetaMongoConfig.new(self)
        @exec = BlankSlate.new
    end

    def is_authed?(m)
        return true
        mask = m.user.mask("%u@%h")
        if @authenticator.authenticated?(mask)
            return true
        end
        m.reply("Please authenticate via %s : %s" % [ Format(:red, "PRIVMSG"), Format(:bold, "!auth username password OTP") ])
        false
    end

    def show_config(m, plugin)
        if is_authed?(m)
            if plugin
                cfgs = @cfg.plugin_configs(plugin)
            else
                cfgs = @cfg.plugins
            end

            if cfgs && !cfgs.empty?
                if plugin
                    m.reply(Format(:bold, plugin) + " = " + cfgs.join('    '))
                else
                    m.reply(Format(:bold, "plugins") + " = " + cfgs.join('    '))
                end
            else
                m.reply("nothing matching '#{plugin}'")
            end
        end
    end

    def get_config(m, expr)
        if is_authed?(m)
            if mm = expr.match(%r{(.*?)\[(.*?)\]})
                plugin, key = mm[1], mm[2]
                m.reply(Format(:bold, expr) + " = " + @cfg.plugin_get_key(plugin, key).to_s)
            else
                show_config(m, expr)
            end
        end
    end

    def set_config(m, expr, vexpr)
        if is_authed?(m)
            if mm = expr.match(%r{(.*?)\[(.*?)\]})
                plugin, key = mm[1], mm[2]
                    begin
                        v = @exec.exec(vexpr)
                        @cfg.plugin_set_key(plugin, key, v)
                        get_config(m, expr)
                    rescue
                        m.reply("Eh?")
                    end
            else
                m.reply("set what?")
            end
        end
    end


end

if __FILE__ == $0
    bot = Cinch::Bot.new do
        configure do |c|
            c.nicks = [ 'gertrude', 'gert', 'gertie', 'gerters', 'ermintrude']
            c.server = "irc.z.je"
            c.channels = ["#gertrude"]
            c.plugins.plugins = [Configs]
        end
    end

    bot.start
end




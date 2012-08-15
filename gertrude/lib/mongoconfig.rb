#!/usr/bin/env ruby

require 'mongo'

class MongoConfig
    # params:
    #   plugin - owning plugin object
    #
    # opts:
    #   host: host of the mongo server (default is localhost)
    #   port: port of the mongo server (default is 27017)
    #   db: the mongo db that contains all the bot's data
    #   collection: the mongo collection containing the bot's plugin data
    def initialize(plugin, useropts={})
        opts = {
            host: 'localhost',
            port: 27017,
            db: 'gertrude',
            collection:'plugin_config'
        }.merge(useropts)

        @plugin = plugin
        @host = opts[:host]
        @port = opts[:port]

        @db_name = opts[:db]
        @coll_name = opts[:collection] 
        @id = @plugin.class.plugin_name
        @mutex = "plgcfg_#{@coll_name}_#{@id}".to_sym

        @db = Mongo::Connection::new(@host, @port).db(@db_name)
        @collection = @db.collection(@coll_name)
    end

    # retrieve a value by key
    def [](key)
        key = key.to_s unless key.is_a? String
        puts "SEARCHING for key '#{key}' in doc '#{@id}'"
        cursor = @collection.find_one( { plgid: @id } )
        if cursor
            return cursor[key]
        end
        nil
    end

    # store a value by key
    def []=(key, value)
        key = key.to_s unless key.is_a? String
        @collection.update( { plgid: @id }, { plgid: @id, key => value }, { upsert: true })
    end
end

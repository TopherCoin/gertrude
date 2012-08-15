#!/usr/bin/env ruby

require 'cgi'
require 'open-uri'
require 'mongo'
require 'nokogiri'
require 'cinch'

module ScraperMethods
    def collection=(collection)
        @collection = collection
    end

    def collection
        @collection
    end
end

# The Scrape class maintains a cached database which is the result of
# running the given block for a webpage scraped from the given URL.
# If we've done this more recently than :lifetime secs, we return the
# old (cached) result, otherwise we perform the scrape afresh.
#
# On startup, if we have no cached database, we preemptively arrange
# to populate one at some random time less than the given lifetime.
# Similarly if we have a database with a stale timestamp; or a valid
# timestamp but a missing database.
class Scrape
    
    EVERY_MINUTE = 60
    EVERY_HALF_HOUR = 30 * EVERY_MINUTE
    EVERY_HOUR = 60 * EVERY_MINUTE
    EVERY_DAY = 24 * EVERY_HOUR
    EVERY_WEEK = 7 * EVERY_DAY
    EVERY_FORTNIGHT = 2 * EVERY_WEEK
    EVERY_MONTH = 4 * EVERY_WEEK
    EVERY_YEAR = 12 * EVERY_MONTH

    HOURLY = EVERY_HOUR
    DAILY = EVERY_DAY
    WEEKLY = EVERY_WEEK
    FORTNIGHTLY = EVERY_FORTNIGHT
    MONTHLY = EVERY_MONTH
    YEARLY = EVERY_YEAR

    # params
    #   plugin: the Cinch::Plugin instance of the calling object
    #
    # options:
    #   host: host of the mongo server (default is localhost)
    #   port: port of the mongo server (default is 27017)
    #   url: the URL to scrape
    #   lifetime: how long the scaped data is valid for, in seconds
    #   db: the mongo db where we will store the results
    #   collection: the mongo collection where we will store the results
    #   drop: if TRUE, delete entire collection just before calling handler/block.
    #   handler: pass an object of class Nokogiri::*::SAX::Document if
    #   you want to do async sax style parsing.
    #   <block>: a lambda which will be responsible for converting
    #   newly-scraped HTML/XML into database entries. The lambda is called
    #   with the entire XML file and the database collection as arguments.
    #   Lambda is only called if no handler: option was specified. It is passed
    #   the mongo collection object and an IO object referencing the data.
    def initialize(plugin, useropts={}, &block)
        opts = {
            host: 'localhost',
            port: 27017,
            db: 'gertrude',
            lifetime: 3600,
            drop: false,
            handler: nil
        }.merge(useropts)

        @plugin = plugin || raise("no plugin!")
        @host = opts[:host]
        @port = opts[:port]

        @db_name = opts[:db]
        @coll_name = opts[:collection] || raise("no collection!")
        @mutex = "cinch_scrape_#{@coll_name}".to_sym

        @url = opts[:url] || raise("no url!")
        @lifetime = opts[:lifetime]

        @handler = opts[:handler] 
        @callback = block || nil
        @drop = opts[:drop]

        @db = Mongo::Connection::new(@host, @port).db(@db_name)
        @collection = @db.collection(@coll_name)

        if @handler
            @handler.extend(ScraperMethods)
            @handler.collection = @collection
        end

        @timestamps = @db.collection("scrape_timestamps")

        if r = @timestamps.find_one( { "client" => @coll_name } )
            @last_scrape = r['timestamp']
        else
            @last_scrape = 0
        end

        if is_stale? || db_empty?
            # schedule timer in (<lifetime) allow 10 secs for startup churn
            interval = rand(@lifetime/2) + 10
            #interval = rand(10) + 10
            @plugin.info "Speculative database acquisition in #{interval} secs"
            set_timer(interval)
        else
            # schedule timer at proper interval
            @plugin.info "Database still valid for #{remaining} secs"
            set_timer(remaining)
        end

    end

    # set a timer in 'secs' seconds, or if none given, in @lifetime secs
    def set_timer(secs=nil)
        secs ||= @lifetime
        cb = method(:timer_callback).to_proc

        # XXX TODO: if we ever implement dynamic reloading of plugins, it
        # is likely that these timers will linger on, as they don't get 
        # cleared out when the owning plugin is unregistered. Investigate
        # raising these on the plugin instance, not on the bot instance.
        @timer = @plugin.Timer(secs, { threaded: true, shots: 1, 
                                  start_automatically: false, stop_automatically: false }, 
                                  &cb)
    end

    # kill_timer doesn't just unschedule and delete the timer object, it terminates
    # any currently running timer handler thread! Therefore a bad idea to call this
    # directly or indirectly from a timer handler.
    def kill_timer
        if @timer
            @timer.stop
            @timer = nil
        end
    end

    def timer_callback
        @plugin.debug "TIMER FIRED"
        do_scraping
        @last_scrape = Time.now
    end

    # is the previous scrape data currently stale?
    def is_stale?
        remaining() > @lifetime
    end

    # how long (from now) does the previous scrape data remain valid?
    def remaining
        (Time.now - @last_scrape).to_i 
    end

    def db_entries; @collection.count; end
    def db_empty?; db_entries == 0; end

    def do_scraping
        @plugin.info "Fetching data from #{@url}..."
        data = open(@url)

        @plugin.bot.synchronize(@mutex) do 
            if @drop
                @plugin.info "Removing old collection..."
                @collection.remove if @collection
            end

            @plugin.info "Parsing data..."
            if @handler
                if @handler.is_a? Nokogiri::XML::SAX::Document
                    p = Nokogiri::XML::SAX::Parser.new(@handler)
                elsif @handler.is_a? Nokogiri::HTML::SAX::Document
                    p = Nokogiri::HTML::SAX::Parser.new(@handler)
                end

                if p
                    p.parse(data)
                end
            else
                @callback.call(@collection, data)
            end

            @plugin.info "Refreshing timestamp..."
            @timestamps.update( { "client" => @coll_name}, 
                                { "client" => @coll_name, "timestamp" => Time.now }, 
                                { upsert: true })
            set_timer
        end
        @collection
    end

    # If we've got cached data, return it, even if it's out of date (the rational
    # being that it is probably in the process of being updated by our background
    # timer).
    # If we haven't got cached data, kill the background timer and do a scrape
    # immediately, then reset the timer. This will result in the user getting
    # fresh data, but probably also a modicum of lag.
    # If this latter case happens, the block if any is executed, giving you a 
    # chance to warn users of a delay.
    def scrape(&block)
        c = nil
        @plugin.bot.synchronize(@mutex) do
            if db_empty?
                kill_timer
                yield if block_given?
                c = do_scraping
            else
                c = @collection
            end
        end
        c
    end
end

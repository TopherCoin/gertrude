#!/usr/bin/env ruby
# the *_clean.csv files appear to have been hand sanitised from their counterparts,
# and it looks like tac-new_cleanup.csv is the master file

require 'optparse'
require 'mongo'

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: merge.rb [options] csv_files"

    opts.on("-d", "--debug", "Enable debugging") { options[:debug] = true }
    opts.on("--db DATABASE", "Export to mongo database") {|db| options[:db] = db }
    opts.on("--collection COLLECTION", "Export to mongo collection") {|c| options[:collection] = c }
    opts.on("-c", "--clean", "Clean old database records before populating") { options[:clean] = true }
end.parse!

tacs = {}

ARGF.each_line do |l|
    row = l.split(%r{[;,]})
    tac = row.shift.to_i
    mf = row.shift.strip
    model = row.shift.strip
    #hw = row.shift
    #os = row.shift
    #year = row.shift

    if mf.empty?
        puts "EMPTY desription for TAC #{tac}"
        mf = "unknown"
    end

    if model.empty?
        puts "EMPTY model for TAC #{tac}"
        model = "unknown"
    end

    puts "TAC: #{tac} MF: #{mf} MODEL:#{model}" if options[:debug]

    if tacs[tac]
        puts "DUPLICATE, prev entry for #{tac} was #{tacs[tac]}"
    else
        tacs[tac] = { mf: mf, model: model}
    end
end

if options[:db] && options[:collection]
    puts "Populating database"
    db = Mongo::Connection::new.db(options[:db])
    coll = db.collection(options[:collection])

    if options[:clean]
        puts "Dropping previous records"
        coll.remove
    end

    tacs.each_pair do |k,v|
        coll.insert({ 'tac' => k, 'mf' => v[:model], 'model' => v[:model]})
    end
end


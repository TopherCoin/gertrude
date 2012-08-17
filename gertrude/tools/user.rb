#!/usr/bin/env ruby
# Add/Remove/Modify users in gertrude's user authentication database

require 'optparse'
require 'mongo'
require 'bcrypt'

options = { db: 'gertrude', collection: 'auths' }

OptionParser.new do |opts|
    opts.banner = "Usage: merge.rb [options] csv_files"

    opts.on("--debug", "Enable debugging") { options[:debug] = true }
    opts.on("--db DATABASE", "Export to mongo database") {|db| options[:db] = db }
    opts.on("--collection COLLECTION", "Export to mongo collection") {|c| options[:collection] = c }

    opts.on("--delete USER", "Delete user from auth database") {|user| options[:delete] = user }
    opts.on("--add USER", "Add user to auth database") {|user| options[:add] = user }
    opts.on("--modify USER", "Modify existing user in auth database") { |user| options[:modify] = user}
    opts.on("--show USER", "Show existing user in auth database") { |user| options[:show] = user}

    opts.on("--password PW", "Set password") {|pw| options[:pw] = pw}
    opts.on("--keys id,api+key,id,api_key...", Array, "set list of Yubikey id/api_keys") {|k| options[:keys] = k}
    opts.on("--add-keys id,api_key,id,api_key...", Array, "add Yubikey identities to list") {|k| options[:addkeys] = k}
    opts.on("--del-keys id,id,...", Array, "Delete Yubikey identities from list") {|k| options[:delkeys] = k}

    opts.on("--dump", "Dump the auth database") { options[:dump] = true }

end.parse!

db = Mongo::Connection::new.db(options[:db])
coll = db.collection(options[:collection])

if user = options[:add]
    raise "no password given" unless options[:pw]
    raise "no yubikeys given" unless options[:keys]
    raise "malformed yubikey list" unless options[:keys].length.even?
    pw, keys = options[:pw], options[:keys]
    keys = Hash[*keys].to_a # convert [a,b,c,d] -> [[a,b],[c,d]]
    hash = BCrypt::Password.create(pw)
    puts "Adding USER='#{user}' HASH='#{hash}' KEYS=[#{keys}]"
    coll.update( {'user' => user}, {'user' => user, 'hash' => hash, 'keys' => keys }, {upsert: true} ) 
elsif user = options[:delete]
    coll.remove({ 'user' => user})
elsif user = options[:modify]
    r = coll.find({ 'user' => user })
    if r
        if pw = options[:pw]
            hash = BCrypt::Password.create(pw)
            r['hash'] = hash
        end

        if keys = options[:keys]
            r['keys'] = Hash[*keys].to_a # convert flat list to [[a,b],[c,d]]
        elsif k = options[:addkeys]
            h1 = Hash[*r['keys']] # old keys as hash
            h2 = Hash[*k.flatten] # new keys as hash
            h3 = h1.merge(h2) # merge 'em in
            r['keys'] = h3.to_a # merge, as list of lists
        elsif dk = options[:delkeys]
            h1 = Hash[*r['keys']] # old keys as hash
            h1.delete_if {|k,v| dk.include? k }
            r['keys'] = h1.to_a
        end
        coll.update({'user' => user}, r)
    end
elsif user = options[:show]
    r = coll.find_one({'user' => user})
    if r
        puts "user: #{r['user']}  hash:#{r['hash']}"
        r['keys'].each {|k| puts "\tyubikey id: #{k[0]} api_key:#{k[1]}" }
    else
        puts "No such user '#{user}'"
    end
end

if options[:dump]
    coll.find().each do |r|
        puts "user: #{r['user']}  hash:#{r['hash']}"
        r['keys'].each {|k| puts "\tyubikey id: #{k[0]} api_key:#{k[1]}" }
    end
end

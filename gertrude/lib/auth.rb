#!/usr/bin/env ruby
# Two Factor authentication module for gertrude.
# Maintains an 'auth' database in mongo, which contains, for each user,
# a salted password hash, and a list of yubikey crypto keys.
# To authenticate, a user needs their password and a registered physical key.
# Authentications are valid for some fixed period of time; once this expires,
# or if the bot restarts, users will have to re-authenticate.
#
# Email addrs. make better usernames than IRC nicks. (or use eg Nickserv
# validated nick).

require 'mongo'
require 'bcrypt'
require './yubico'

class Authenticator
    attr_reader :last_result, :validity, :two_factor
    def initialize(opts = {})
        options = {
            twofactor: true,
            validity:600,
            db: "gertrude",
            collection: "auths",
        }.merge(opts)

        @two_factor = options[:twofactor]
        @validity = options[:validity]
        @auth_users = {}
        @last_result = "NO_ERROR"

        @db = Mongo::Connection::new.db(options[:db])
        @collection = @db.collection(options[:collection])
    end

    def authenticate(user, password, otp)
        r = @collection.find_one({ 'user' => user })
        if r
            hash = BCrypt::Password.new(r['hash'])
            if hash == password
                return unless @two_factor
                yubikeys = r['keys']
                yubikeys.each do |y|
                    id = y[0]
                    api_key = y[1]
                    y = Yubico.new(id, api_key)
                    @last_result = y.verify(otp)
                    if @last_result == Yubico::E_OK
                        @auth_users[user] = Time.now
                        return true
                    end
                end
            else
                @last_result = "BAD PASSWORD"
            end
        end
        false
    end

    def authenticated?(user)
        if t = @auth_users[user]
            if(Time.now - t) <= @validity
                return true
            end
        end
        false
    end
end

if __FILE__ == $0
    # test authentication: expects args to be [username] [password] [yubikey-OTP]
    a = Authenticator.new()
    if a.authenticate(*ARGV)
        puts "**AUTHENTICATED**"
    else
        puts "**FAILED** (#{a.last_result})"
    end
end


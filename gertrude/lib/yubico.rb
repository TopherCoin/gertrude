#!/usr/bin/env ruby
#
# Yubico.rb - yubikey authentication library
#
# Author: Jenecai 'Seven' Corvina <seven@ofhearts.org>
#
# Documentation: Jenecai 'Seven' Corvina
#
#
# (C) Copyright 2007 Yubico AB.  All Rights Reserved.
#
# Yubico AB shall have no responsibility, financial or
# otherwise, for any consequences arising out of the use of
# this material. The program material is provided on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
#
# Distributed under an Apache License
# http://www.apache.org/licenses/LICENSE-2.0
#
# == Overview
#
# The Yubikey is a simple tool to for which to authenticate users
# without the hassle of usernames or passwords, in a secure manner.
# Using OTP, the Yubikey is a strong cryptographic tool which, through
# various APIs, calls home to a server, parses the OTP token, and responds
# with authority.
#
# == Introduction
#
# The Yubikey was designed for ease-of-use as well as ease-of-implementation; 
# a veritable solution for all interests where authentication, identity and 
# anonymity are desired or needed. For that logic, the implementation of the 
# API falls under the same concept.
#
# Basic usage of the Yubico module follows the simple Objective concept. 
# Requests centralize about the shared key, so the object you create is 
# singular to that shared secret. The shared secret provided to you as a 
# client service is passed, with your client ID, to the object, to create 
# the instance. (This object will be used
# in all the documentation following.)
#
#  shared_secret = "Th1sIZ4f4k3K3y="
#  yk = Yubico.new 2, shared_secret
#    # => #<Yubico:0x5841d4 @_id=2, @_key="Th1sIZ4f4k3K3y=">
#
# This will initialize the object, provide the two variables @_id and 
# @_key, which are used extensively through the code. If you only need to 
# be verifying OTPs (these requests are unsigned), you can still provide
# the key to verify the signature on the response.
#
# yk = Yubico.new 2
#   # => #<Yubico:0x58bd08 @_id=2, @_key="">
#
# This initializes an object that will make verify requests, but will always 
# return +E_MISSING_SECRET+ when a signed request is called.
#
# == Signatures
#
# Signatures are handled via HMAC SHA1.
#
# == To Be Implemented
#
# Key management classes to add and delete YubiKeys. 
#

require 'net/http'
require 'uri'
require 'digest/sha1'
require 'digest/md5'

require 'openssl'

debug = true;

class Yubico

  # Returned if all is well with the request.
  E_OK = "OK"
  
  # Returned if the server has seen that OTP for that key before.
  E_REPLAYED_OTP = "REPLAYED_OTP"
  
  # Returned if the OTP is invalid or misformed.
  E_BAD_OTP = "BAD_OTP"
  
  # Returned if such a client doesn't exist
  E_NO_SUCH_CLIENT = "NO_SUCH_CLIENT"
  
  # Returned if a specified request violates the rules for the verifier.
  # Typically this happens when you send an unsigned request but the verifier 
  # is set up to only use signed requests.
  E_POLICY_VIOLATION = "POLICY_VIOLATION"
  
  # Returned if the signature on the request was invalid.
  E_BAD_SIGNATURE = "BAD_SIGNATURE"
  
  # Returned if the operation is not allowed, or otherwise denied.
  E_OPERATION_NOT_ALLOWED = "OPERATION_NOT_ALLOWED"
  
  # Returned if a parameter is bad or missing, respectively. (Also returns 
  # an "info" field -- needs to be parsed (1) )
  E_INCORRECT_PARAMATER = "INCORRECT_PARAMETER"
  E_MISSING_PARAMETER = "MISSING_PARAMETER"
  
  # Returned on a Backend Error
  E_BACKEND_ERROR = "BACKEND_ERROR"
  
  # Returned when the object is constructed without a shared key, on requests 
  # that require the shared key.
  E_MISSING_SECRET = "MISSING_SECRET"
  
  # Returned on an unknown error server side.
  E_UNKNOWN_ERROR = "UNKNOWN_ERROR"
  
  
  # The requested client or verifier ID for the instance of the object.
  attr_accessor :_id
  
  # The shared key, if required, for the client or verifier.
  attr_accessor :_key
  
  # The response from the server.
  attr_accessor :_res
  
  # Initialization is used to create the instance variables at creation.
  # Yubikey.new requires in the least an ID, and also takes a shared key.
  def initialize(id, key='')
    @_id = id
    @_key = key
  end
  
  public
          
  # Verify an Yubikey OTP Token. Returns the value of the response 
  # variable "status"
  #   req = yk.verify( @token, @id )
  #     # => STATUS_VARIABLE
  # Upon an error, you should use the Yubikey.last_response method for 
  # a more detailed collection of
  # variables, including the request hash, info and further.
  def verify( otp, id = @_id )
    @_id = id if @_id.nil?

    # Set up the full URL for the request, then pass it through 
    # the +URI+ gauntlet.
    fullurl = "http://api.yubico.com/wsapi/verify?id="+ (@_id.to_s) +
      "&otp="+ otp
    url = URI.parse(fullurl)

    # Make the call to the server and return the full response, not just 
    # the body (to be used later)
    res = Net::HTTP.start(url.host, url.port) { |http|
      http.get((url.path + "?" + url.query))
    }

    # Parse and find the status within the response's body, to verify 
    # this is, in fact, what we're looking for.
    if ( !(/status=([a-zA-Z0-9_]+)/.match(res.body)) )
      # If it's not, let's raise an error.
      raise "Response Error: "+ res.body
    else 
      @_res = res.body
    end

    # Finally, return the response value.

    # AJS mods below
    # @_res.scan(/status=([a-zA-Z0-9_]+)[\s]/).first.to_s
    if m = @_res.match(/status=([a-zA-Z0-9_]+)/)
        return m[1]
    end
    E_UNKNOWN_ERROR
  end
    
  # Return the last available Yubikey response body, in full, for parsing.
  #   req = yk.verify( @token, @_id )
  #   res = req.last_response
  #     # => "h=...\nstatus=OK"
  #
  # On an error, there will be many fields returned by this function you 
  # can sift out manually
  # using regular expressions (to be implemented: last_response returns 
  # an associative array of the
  # response.) for various variables.
  #   req = yk.verify( @token, @_id )
  #     # => "h=Z/D42NucC1nSlIVZqFPR3RO5dG4=\r\nt=2007-10-23T14:26:48Z\
  #           \r\nstatus=REPLAYED_OTP\r\n\r\n"
  #   res = yk.last_response
  #   res["h"]
  #     # => "h=Z/D42NucC1nSlIVZqFPR3RO5dG4="
  #   res["t"]
  #     # => "2007-10-23T14:26:48Z"
  #   res["status"]
  #     # => "REPLAYED_OTP"
  #   res["info"]
  #     # => nil
  #
  def last_response
    hash = @_res.scan(/h=([\w_\=\/]+)[\s]/).first
    timestamp = @_res.scan(/t=([\w\-:]+)[\s]/).first
    status = @_res.scan(/status=([a-zA-Z0-9_]+)[\s]/).first
    info = @_res.scan(/info=([\w\t\S\W]+)/).first
    
    return { "h" => hash, "t" => timestamp, "status" => status, "info" => info }
  end
  
  # Requests add_key information from the server and returns all the information
  # required to encode a Yubikey. This command will create a new key on request,
  # so standard practice should be very secure and sure before this is called.
  #
  #   if( user.created? )
  #     user.keyflag = yk.add_key( @_id, timestamp )
  #     user.keydata = yk.last_response
  #   end
  #     # => 
  def add_key( id, nonce )
    if not @_key
      return E_MISSING_SECRET
    end
    
    operation = "add_key"
    mesg = "id=#{id}&nonce=#{nonce}&operation=#{operation}"
    key = self.hmac( @_id, mesg, 'sha1' )
    
    url = URI.parse("http://api.yubico.com/wsapi/add_key?operation=#{operation}&id=#{id}&nonce=#{nonce}&h=#{key}")
    url.port = 80
    res = Net::HTTP.start(url.host, url.port) { |http|
      http.get( url.path + "?" + url.query )
    }
    
    if( ( res.body ) && ( /status=([\w_]+)[\s]/.match(res.body) ) )
      @_res = res.body
      return res.body.scan(/status=([\w_]+)[\s]/).first
    else
      return E_UNKNOWN_ERROR
    end     
  end
  
  # Signed request that deletes key +key_id+ from the server, with the 
  # client ID +id+
  # and passes +nonce+ as the request nonce.
  def delete_key( id, key_id, nonce )
    if not @_key
      return E_MISSING_SECRET
    end
    
    operation = "delete_key"
    mesg = "key_id=#{key_id}&id=#{id}&nonce=#{nonce}&operation=#{operation}"
    key = self.hmac( @_id, mesg, 'sha1' )
    
    url = URI.parse("http://api.yubico.com/wsapi/delete_key?#{mesg}&h=#{key}")
    url.port = 80
    res = Net::HTTP.start(url.host, url.port) { |http|
      http.get( url.path + "?" + url.query )
    }
    
    if( (res.body) && ( /status=([\w_]+)[\s]/.match(res.body) ) )
      @_res = res.body
      return res.body.scan(/status=([\w_]+)[\s]/).first
    else
      return E_UNKNOWN_ERROR
    end
  end
  
  # Define the headers for our signed requests.
  headers = {
    "user-agent" => "Yubico::Auth Ruby 1.0",
    "x-hopbyhop" => "Magic happens here."
  }
  
  # Takes the OTP, shared key, and ID, creates the RFC3339 timestamp, 
  # and returns the hash.
  #   hash = yubikey_object.signKey( @otp, @shared, @id )
  #     # => "39ccb32d95edfdbcd882f2b01809724ec640ea16"
  def hmac( key, msg, algorithm )
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new(algorithm), key, msg)
  end
                
end

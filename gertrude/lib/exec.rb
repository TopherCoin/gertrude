#!/usr/bin/env ruby

require 'timeout'

# create a new blank slate object, and add the binding() method
class BlankSlate < BasicObject

    # provide result of previous evaluations - can't be written
    # to from within the sandbox
    attr_accessor :ans

    class Timeout < ::Exception
        # default set_backtrace attempts to modify instance variables,
        # which we can't allow from inside a $SAFE=4 environment
        def set_backtrace(*args); end
    end

=begin
    def binding; ::Kernel.binding; end
    def proc(*args); ::Kernel.proc(*args); end
    
    # this method requires the two delegator methods above
    # exec2 doesn't have this requirement
    def execX(s)
        s.untaint

        # inside a proc we can temporarily elevate our SAFE level
        result = proc do
            $SAFE = 4
            # binding() is private, hence instance_eval
            instance_eval do
                binding
            end.eval(s)
        end.call
    end
=end

    # execute an arbitrary expression in a sandbox, at $SAFE=4
    # and in a highly limited environment.
    # expressions which take longer than a second to execute
    # will be terminated.
    def exec(s)
        s.untaint

        begin
            begin
                x = ::Thread.current
                y = ::Thread.start {
                    begin 
                        ::Kernel.sleep 1
                    rescue => e
                        x.raise e
                    else
                        e = ::BlankSlate::Timeout.new("timeout")
                        x.raise e
                    end
                }

                # inside a proc we can temporarily elevate our SAFE level
                @ans = ::Kernel.proc do
                    $SAFE = 4
                    # binding() is private, hence instance_eval
                    instance_eval do
                        ::Kernel.binding
                    end.eval(s)
                end.call
            ensure
                if y
                    y.kill
                    y.join
                end
            end
        rescue => e
            ::Kernel.raise e
        end
    end

    # add methods which will be visible in the sandbox
    def sqrt(x); ::Math.sqrt(x); end
    def sin(x); ::Math.sin(x); end
    def sinh(x); ::Math.sinh(x); end
    def asin(x); ::Math.asin(x); end
    def asinh(x); ::Math.asinh(x); end
    def cos(x); ::Math.cos(x); end
    def cosh(x); ::Math.cosh(x); end
    def acos(x); ::Math.acos(x); end
    def acosh(x); ::Math.acosh(x); end
    def tan(x); ::Math.tan(x); end
    def tanh(x); ::Math.tanh(x); end
    def atan(x); ::Math.atan(x); end
    def atanh(x); ::Math.atanh(x); end
    def cbrt(x); ::Math.cbrt(x); end
    def exp(x); ::Math.exp(x); end
    def log(x,b=::Math::E); ::Math.log(x,b); end
    def log10(x); ::Math.log10(x); end
    def log2(x); ::Math.log2(x); end

    def base(b,x)
        case x
        when ::String
            x.to_i(b)
        else
            x.to_s(b)
        end
    end
    
    def oct(x); base(8,  x); end
    def bin(x); base(2,  x); end
    def hex(x); base(16, x); end

    def rad2deg(r); (r*180)/::Math::PI; end
    def deg2rad(d); (d*::Math::PI)/180; end

    # add constants which will be visible in the sandbox
    E = ::Math::E
    PI = ::Math::PI
    C = 299792458        # speed of light
    G = 6.6738480e-11    # gravitational constant
    H = 6.6260695729e-34 # Planck constant
    L = 6.0221412927e23  # Avogadro's number
    F = 96485.336521     # Faraday's constant
    R = 8.314462175      # Gas constant
    GEE = 9.80665        # acceleration of earth gravity
end

if __FILE__ == $0
    clean_room = BlankSlate.new

    loop do
        begin
            command = gets
            exit if command.start_with? "exit"
            puts clean_room.exec(command)
        rescue BlankSlate::Timeout => e
            puts "Taking too long"
        rescue SecurityError => e
            puts "Naughty!"
        # StandardError because "rescue Exception" traps SIGTERM
        rescue StandardError => e 
            puts "Off limits: #{e}"
        end
    end
end


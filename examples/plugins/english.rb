#!/usr/bin/env ruby


class NumberParser
    # short or long scale - alters meaning of 'billion' etc
    SHORT = 1 # US/UK
    LONG =  2 # Europe 

    def NumberParser.exp(s)
        (s > 0) ? Math.log10(s).floor : 0
    end

    class NPSimple
        def initialize(aliases, lvalue)
            @lvalue = lvalue
            @svalue = lvalue
            @aliases = aliases
            @match = Regexp.new("\\A\\s*(#{@aliases.join('|')})")
            @lexp = NumberParser.exp(@lvalue)
            @sexp = @lexp
        end

        # simple atoms combine with the topmost element on the stack
        def evaluate(stack, scale)
            value = (scale == SHORT) ? @svalue : @lvalue
            exp   = (scale == SHORT) ? @sexp   : @lexp

            prev = stack.pop

            if prev.nil?
                puts "stack slot empty, seeding #{value}"
                stack.push value
            else
                pexp = NumberParser.exp(prev)

                if exp == pexp
                    stack.push(prev * (10 ** (exp+1)) + value)
                elsif exp < pexp
                    stack.push(prev + value)
                    puts "prev was #{prev} stack now #{stack}"
                else
                    stack.push(prev * value)
                    puts "prev was #{prev} stack now #{stack}"
                end
            end
        end

        # parse the string. if successful, return unparsed portion of string, and stack the parse result.
        # if unsuccessful, return nil.
        def parse(s, stack=[], opts={})
            scale = opts[:scale] || SHORT
            separator = opts[:separator] || ','

            if m = s.match(%r{\A\s*(and|[#{separator}])})
                s = m.post_match
            end

            if m = s.match(@match)
                puts "MATCHED #{@match}"
                evaluate(stack, scale)
                puts "POSTMATCH stack: #{stack} remains:#{m.post_match}"
                return m.post_match
            end 
            return nil
        end

        def match?(s)
            parse(s) != nil
        end
    end

    class NPComplex < NPSimple

        def initialize(aliases, lvalue, svalue)
            super(aliases, lvalue)
            @svalue = svalue
            @sexp = NumberParser.exp(@svalue)
        end

        # complex atoms combine with teh topmost element on the stack,
        # and then start a new stack frame for subsequent atoms
        def evaluate(stack, scale)
            super
            stack.push nil
        end
    end

    def initialize
        @parselets = []
        simples = {
            one:['a', 1], two:2, three:3, four:4, five:5, six:6, seven:7, eight:8, nine:9, zero:0,
            ten:10, eleven:11, twelve:['dozen', 12], thirteen:13, fourteen:14, fifteen:15, 
            sixteen:16, seventeen:17, eighteen:18, nineteen:19, 
            twenty:['score', 'pony', 'ponies', 20], thirty:30, forty:40, fifty:50, sixty:60, seventy:70, eighty:80, ninety:90,
            hundred:100, monkey:['monkeys', 'monkies', 500]
        }

        comps = {
            thousand:['grand', 'large', 1000, 1000],
            million: [ 1e6, 1e6],
            milliard: [ 1e9, 1e9],
            billion: [ 1e9, 1e12],
            trillion: [ 1e12, 1e18],
            quadrillion: [ 1e15, 1e24],
            quintillion: [ 1e18, 1e30],
            sextillion: [ 1e21, 1e36],
            septillion: [ 1e24, 1e42],
            octillion: [ 1e27, 1e48],
            nonillion: [ 1e30, 1e54],
            decillion: [ 1e33, 1e60],
        }

        simples.each do |k,v|
            case v
            when Array
                value = v.pop
                names = v.unshift(k.to_s)
            else
                value = v
                names = [k.to_s]
            end
            @parselets.push NPSimple.new(names, value)
        end

        comps.each do |k, v|
            lvalue = v.pop
            svalue = v.pop
            names = v.unshift(k.to_s)
            @parselets.push NPComplex.new(names, lvalue, svalue)
        end
    end

    def parse(s, opts={})
        puts "STARTED: s: #{s}"
        stack = []
        enum = @parselets.each
        loop do
            begin
                p = enum.next
                if n = p.parse(s, stack, opts)
                    s = n
                    enum.rewind
                end
            rescue StopIteration
                puts "FINISHED: stack: #{stack} s: #{s}\n\n"
                return stack.compact.reduce(:+)
            end
        end
    end
end

if __FILE__ == $0
    require 'expectations'

    np = NumberParser.new
    Expectations do
        # simples
        expect(np.parse("one")) == 1
        expect(np.parse("two")) == 2
        expect(np.parse("three")) == 3

        expect(np.parse("eleven")) == 11
        expect(np.parse("twelve")) == 12
        expect(np.parse("thirteen")) == 13

        expect(np.parse("twenty")) == 20
        expect(np.parse("pony")) == 20
        expect(np.parse("thirty")) == 30
        expect(np.parse("forty")) == 40

        #complexes
        expect(np.parse("hundred")) == 100
        expect(np.parse("thousand")) == 1000
        expect(np.parse("million")) == 1000000
        expect(np.parse("billion")) == 1000000000
        expect(np.parse("billion", scale: NumberParser::SHORT)) == 1000000000
        expect(np.parse("billion", scale: NumberParser::LONG))  == 1000000000000
        expect(np.parse("trillion")) == 1000000000000
        expect(np.parse("trillion", scale: NumberParser::SHORT)) == 1000000000000
        expect(np.parse("trillion", scale: NumberParser::LONG))  == 1000000000000000000

        # simple compound
        expect(np.parse("twenty one")) == 21
        expect(np.parse("forty two")) == 42

        expect(np.parse("two hundred")) == 200
        expect(np.parse("five hundred six")) == 506
        expect(np.parse("five hundred and six")) == 506
        expect(np.parse("a hundred and six")) == 106

        # complex compound
        expect(np.parse("five thousand four hundred twenty six")) == 5426
        expect(np.parse("five thousand four hundred and twenty six")) == 5426
        expect(np.parse("five thousand, four hundred and twenty six")) == 5426

        expect(np.parse("five hundred and thirteen thousand, four hundred and twenty six")) == 513426
        expect(np.parse("eight hundred and twenty six million, five hundred and thirteen thousand, four hundred and twenty six")) == 826513426

        # simple enumeration style "one two three" => 123
        expect(np.parse("one two")) == 12
        expect(np.parse("one two three")) == 123
    end
end

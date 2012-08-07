#!/usr/bin/env ruby

# A simple parser for English natural number phrases. Almost comprehensive,
# but barfs on some complicated terminals that appear both in prefix and
# suffix expressions. Probably requires a proper TDOP parser to do it justice.

class NumberParser
    # short or long scale - alters meaning of 'billion' etc
    SHORT = 1 # US/UK
    LONG =  2 # Europe 

    UNITS = 0
    TENS = 1
    HUNDREDS = 2

    def NumberParser.exp(s)
        (s > 0) ? Math.log10(s).floor : 0
    end

    # a frame is either a single numeric, or a list of numerics
    # which are in the same decade range (eg all units, all tens)
    class NPFrame
        def initialize(n)
            @elems = [n]
        end

        def exp
           if @elems.last 
               NumberParser.exp(@elems.last)
           else
               0
           end
        end 
        
        def >>(n)
            @elems.push(n)
            self
        end

        def +(n)
            p = @elems.pop || 0
            @elems.push(p + n)
            self
        end

        def *(n)
            p = @elems.pop || 1
            @elems.push(p * n)
            self
        end

        def reduce
            # to_f necessary because to_i can't deal with scientific notation
            @elems.join.to_f.to_i
        end

        def to_s
            @elems.to_s
        end
    end

    # a stack of NPFrames; a new frame is constructed after we
    # encounter an NPComplex.
    # stack is summed to produce the final result.
    class NPStack
        def initialize
            @frames = []
        end

        def pop
            @frames.pop
        end

        def push(n)
            raise "can only push NPFrames, not #{n.class}" unless n.is_a? NPFrame
            @frames.push(n)
        end

        # init a new stack frame when we see a NPComplex
        def save
            push NPFrame.new(nil)
        end

        def reduce
            return nil if @frames.compact.empty?

            total = @frames.inject(0) do |acc,n|
                acc += n.reduce
            end
        end

        def to_s
            @frames.to_s
        end
    end

    class NPSimple
        def initialize(aliases, lvalue)
            @lvalue = lvalue
            @svalue = lvalue
            @aliases = aliases
            # regex is union of aliases, longest match first
            @match = Regexp.new("\\A\\s*(#{@aliases.sort {|a,b| b.length <=> a.length}.join('|')})")
            @lexp = NumberParser.exp(@lvalue)
            @sexp = @lexp
        end

        # the canonical name is the first name in the list of aliases for this
        # quantity. canonical names are treated slightly differently, to allow
        # us to map "three twenty" => 320 but 'three score' => 60.
        def canonical_name
            @aliases.first
        end

        # simple atoms combine with the topmost element on the stack
        def evaluate(stack, scale, is_canon)
            value = (scale == SHORT) ? @svalue : @lvalue
            exp   = (scale == SHORT) ? @sexp   : @lexp

            prev = stack.pop

            if prev.nil?
                puts "stack slot empty, seeding #{value}"
                stack.push NPFrame.new(value)
            else
                pexp = prev.exp

                # if the rank of the current value is the same as the rank of the previous
                # value, then we push the current value onto the previous value; thus expressions
                # like "one two three" become [1,2,3] which when flattened will produce 123.
                # Similarly, "twenty twelve" => [20, 12] => 2012.
                if exp == pexp 
                    stack.push(prev >> value)

                # if the rank of the current value is less than the rank of the previous value
                # then we are in "fifty one" / "hundred ten" etc territory. Simply add the 
                # current value to the (last member of the) previous value.
                elsif exp < pexp
                    stack.push(prev + value)
                    puts "prev was #{prev} stack now #{stack}"

                # if the rank of the current value is greater than the rank of the previous value
                # then we are in "hundred thousand" / "one twenty" / "five hundred" territory.
                # If current value is UNITS or TENS, then we push its value. This allows us to deal
                # with expressions like "one twenty" => [1,20] => 120.
                # Otherwise, we are dealing with an expression like "five hundred" => 500
                # One final special case, is that we treat canonical names differently from the
                # other aliases in the UNITS and TENS case.
                # If it's canonical, proceed as above (push), otherwise multiply (instead of push).
                # This allows us to do "three twenty" => [3,20] => 320 
                # but also  "three score" => 60.
                else 
                    if [UNITS,TENS].include?(exp) && is_canon
                        stack.push(prev >> value)
                    else
                        stack.push(prev * value)
                    end
                    puts "prev was #{prev} stack now #{stack}"
                end
            end
        end

        # parse the string. if successful, return unparsed portion of string, and stack the parse result.
        # if unsuccessful, return nil.
        def parse(s, stack=[], opts={})
            scale = opts[:scale] || SHORT

            puts "TRY: '#{s}' && #{@match}"

            if m = s.match(@match)
                puts "MATCHED #{@match}"
                evaluate(stack, scale, m[1] == (canonical_name))
                puts "POSTMATCH stack: #{stack} remains:#{m.post_match}"
                return m.post_match
            end 
            return nil
        end

        def match?(s)
            parse(s) != nil
        end
    end

    # NPComplex is like NPSimple, except that NPComplex quantities start a new stack frame,
    # they correspond to the commas in eg "one hudred million, five hundred thousand, and two"
    # (even though the commas may be elided).
    # Additionally, NPComplex can have both "short scale" and "long scale" values to cater
    # for differing opinions about what exactly "billion" et al mean.
    class NPComplex < NPSimple

        def initialize(aliases, lvalue, svalue)
            super(aliases, lvalue)
            @svalue = svalue
            @sexp = NumberParser.exp(@svalue)
        end

        # complex atoms combine with teh topmost element on the stack,
        # and then start a new stack frame for subsequent atoms
        def evaluate(stack, scale, is_canon)
            super
            stack.save
        end
    end

    def initialize
        @names = []
        @parselets = []

        simples = {
            # order is important - we want to try matching 'sixty' before we try 'six'
            ten:['tenner', 'tenner', 'tenners', 'ayrton', 'ayrton', 'ayrtons', 10], eleven:11, twelve:['dozen', 12], thirteen:13, fourteen:14, fifteen:15, 
            sixteen:16, seventeen:17, eighteen:18, nineteen:19, 
            twenty:['score', 20], 
            pony: ['ponies', 'a pony', 25], thirty:30, forty:40, # need to include 'a pony' coz it's TENS
            fifty:['bullseye', 'bullseyes', 'a bullseye', 'nifty', 'niftys', 'nifties','a nifty', 50], # need to include 'a bullseye' etc coz it's TENS
            sixty:60, seventy:70, eighty:80, ninety:90,
            hundred:['ton', 'tonne', 'century', 100], monkey:['monkeys', 'monkies', 500],
            two:2, three:3, four:4, five:['lady', 'ladies', 'jackson', 'jacksons', 5], six:6, seven:7, eight:8, nine:9, zero:0,
            # one:['a', 'an', 1] - special case, defined below
        }

        comps = {
            thousand:['grand', 'large', 1000, 1000],
            xxtwothousand:['archer', 'archers', 2000, 2000], # canonical name not used
            million: [ 'bernie', 'bernies', 1e6, 1e6],
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
            # there are many more...
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
            add_names(names)
            @parselets.push NPSimple.new(names, value)
        end

        comps.each do |k, v|
            lvalue = v.pop
            svalue = v.pop
            names = v.unshift(k.to_s)
            add_names(names)
            @parselets.push NPComplex.new(names, lvalue, svalue)
        end

        # special case for 'one' - match this last as it has the short aliases
        # 'a' and 'an'
        @parselets.push NPSimple.new(['one', 'an', 'a'], 1)
    end

    # accept a list of names and add them to our list of matches to detect a potential candidate string
    def add_names(a)
        @names += a.select {|n| n.length > 2 }
        @names.uniq!
    end

    # a rough metric to determine if the candidate string is likely to be parsable
    def candidate?(s)
        r = %r{(#{@names.join('|')})}
        return true if s.match(r)
        false
    end

    # strip off leading commas, 'and's etc
    def strip_separators(s, opts={})
        separator = opts[:separator] || ','

        while m = s.match(%r{\A\s*(and|[#{separator}])})
            puts "CLOBBERED #{m[1]}"
            s = m.post_match
        end
        s
    end

    # given a string s, replace all numeric phrases it contains
    # with the numerical equivalent value, and leave unparseable
    # string fragments intact. Return is thus an array, eg:
    # [100, "divided by", 20]
    def replace_a(s, opts={})
        results = []

        until s.empty?
            # first try to parse a number at head of string
            if r = parse!(s, opts)
                results.push r
            else
                # discard the head word
                n = s.partition(%r{\s+})
                puts "DISCARD #{n[0]} and reparse with #{n[-1]}"
                results.push n[0] unless n[0].empty?
                s = n[-1]
            end
        end
        results
    end

    # as above, but return a string
    def replace(s, opts={})
        a = replace_a(s, opts)
        a.join(' ')
    end


    # parse a numeric phrase at the start of a string, and return
    # its numeric value, or nil if none found.
    # The input string is modified to leave any remaining text
    # fragment.
    def parse!(s, opts={})
        puts "STARTED: s: #{s}"
        s = strip_separators(s, opts)
        stack = NPStack.new
        enum = @parselets.each
        loop do
            begin
                p = enum.next
                if n = p.parse(s, stack, opts)
                    s.replace strip_separators(n, opts)
                    enum.rewind
                end
            rescue StopIteration
                r = stack.reduce
                puts "FINISHED: stack: #{stack} s: #{s} ret:#{r}\n\n"
                return r
            end
        end
    end

    def parse(s, opts={})
        parse!(s.dup, opts)
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
        expect(np.parse("pony")) == 25
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

        expect(np.parse("a hundred")) == 100
        expect(np.parse("a hundred and six")) == 106
        expect(np.parse("two hundred")) == 200
        expect(np.parse("five hundred six")) == 506
        expect(np.parse("five hundred and six")) == 506
        expect(np.parse("a hundred and six")) == 106

        # complex compound
        expect(np.parse("five thousand four hundred twenty six")) == 5426
        expect(np.parse("five thousand four hundred and twenty six")) == 5426
        expect(np.parse("five thousand, four hundred and twenty six")) == 5426

        expect(np.parse("five hundred and thirteen thousand, four hundred and twenty six")) == 513426
        expect(np.parse("five hundred and thirteen thousand four hundred and twenty six")) == 513426
        expect(np.parse("five hundred thirteen thousand four hundred twenty six")) == 513426
        expect(np.parse("two hundred and sixty seven thousand, seven hundred and nine")) == 267709 # to one against, and falling...
        expect(np.parse("two hundred sixty seven thousand, seven hundred nine")) == 267709 
        expect(np.parse("two hundred sixty seven thousand seven hundred nine")) == 267709 
        expect(np.parse("eight hundred and twenty six million, five hundred and thirteen thousand, four hundred and twenty six")) == 826513426
        expect(np.parse("eight hundred and twenty six million five hundred and thirteen thousand four hundred and twenty six")) == 826513426
        expect(np.parse("eight hundred twenty six million five hundred thirteen thousand four hundred twenty six")) == 826513426

        # simple enumeration style "one two three" => 123
        expect(np.parse("one two")) == 12
        expect(np.parse("one two three")) == 123
        expect(np.parse("twenty twelve")) == 2012
        expect(np.parse("one twenty")) == 120
        expect(np.parse("twelve hundred")) == 1200
        expect(np.parse("one twenty hundred")) == 12000 # bit unnatural

        # canonical names
        expect(np.parse("two twenty")) == 220
        expect(np.parse("two score")) == 40
        expect(np.parse("five twelve")) == 512
        expect(np.parse("five dozen")) == 60

        # cockney
        expect(np.parse("three grand two monkies and a pony")) == 4025
        expect(np.parse("two large")) == 2000
        expect(np.parse("a pony")) == 25
        expect(np.parse("two ponies")) == 50
        expect(np.parse("a monkey")) == 500
        expect(np.parse("two monkies")) == 1000
        expect(np.parse("two nifties")) == 100
        expect(np.parse("a score")) == 20
        expect(np.parse("two score")) == 40
        expect(np.parse("a tenner")) == 10
        expect(np.parse("three tenners")) == 30
        expect(np.parse("a bernie")) == 1000000
        expect(np.parse("a bernie and three archers")) == 1006000
        expect(np.parse("a bernie, three archers, and a monkey")) == 1006500
        expect(np.parse("a bernie, three archers and a grand, and a monkey")) == 1007500
        expect(np.parse("a bernie, three archers and a grand, and a monkey, and a nifty")) == 1007550
        #expect(np.parse("a bernie, three archers and a grand, a monkey and two nifties")) == 1007600
        
        # test destructive parser
        expect " pence" do
            s = "twenty pence"
            np.parse!(s)
            s
        end

        # test replacement
        expect [20, "pence"] do
            np.replace_a("twenty pence")
        end

        expect [20, "divided", "by", 30] do
            np.replace_a("twenty divided by thirty")
        end
        
    end
end

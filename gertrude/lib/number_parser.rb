#!/usr/bin/env ruby
# NumberParser tries to parse natural English descriptions of numbers
# into actual integers, using either a traditional form, eg "one hundred
# and thirty eight thousand", or the American form "one three eight oh oh oh",
# or even the year-like system "twenty twelve", or any combination of the
# above. It will even have a stab at cockney slang.
# So far I've been unable to come up with a consistent means of parsing 
# fractions, due to apparent language ambiguities: for example, is
# "twenty two hundredths" equal to 20/200 or 22/100?
class NumberParser

    # whether to use the Long Scale or the Short Scale (for billion, etc)
    SHORT = 1
    LONG = 2

    # names of some common ranks
    UNIT = 1
    TEN = 10
    HUNDRED = 100
    THOUSAND = 1000

    class Token
        attr_reader :name, :value, :rank

        def initialize(name, value)
            @name = name
            @value = value

            # rank is 1 for UNITs, 10 for TENs, 100 for HUNDREDs etc
            @rank = case value
                    when String
                        nil
                    else
                        10**(self.decades - 1)
                    end
        end

        def has_rank?(*a); a.flatten.find {|p| p == @rank}; end

        def match(s); s.strip.index(@name) == 0; end

        def to_s; @name.upcase + "<#{@value}>"; end

        # how many decades our value occupies eg 9=>1d, 99=>2d, 999=>3d
        def decades
            return 1 if @value == 0
            Math.log10(@value).floor + 1
        end

        # how much we would have to divide our value by to put the
        # decimal point on its immediate left
        def scale; 10**self.decades; end

        # shift 'a' up so that it occupies the decades immediately
        # above our value.
        # eg. shifting 20 into @value=12 => 2012
        def shift_up(a); a * self.scale + @value; end

        # reduce arr by modifying arr; return TRUE if changes made
        def reduce!(arr, idx, level=1)
            nxt = arr[idx+1]
            prv = (idx > 0) ? arr[idx-1] : nil
            case level
            when 99 # at level 99 we collate adjacent tokens with addition
                if nxt
                    unless nxt.is_a?(Verbatim) 
                        @value = @value + nxt.value
                        arr.delete_at(idx+1)
                        return true
                    end
                end
                # done collating, replace Token with its value
                arr[idx] = @value
            end
            false
        end
    end


    class Unit < Token
        # reduce arr by modifying arr; return TRUE if changes made
        def reduce!(arr, idx,level=1)
            nxt = arr[idx+1]
            prv = (idx > 0) ? arr[idx-1] : nil
            case level
            when 1 # absorb UNITs to the RIGHT
                if nxt
                    if nxt.is_a? Unit
                        #@value = @value * 10 + nxt.value
                        @value = nxt.shift_up(@value)
                        arr.delete_at(idx+1)
                        return true
                    end
                end
            # both UNITs and TENs have aglutinated into larger strings,
            # we now merge sequences of alternate UNIT/TEN/UNIT/TEN...
            when 2
                if nxt # absorb TENs/UNITs to the RIGHT
                    if nxt.has_rank?(TEN, UNIT)
                        @value = nxt.shift_up(@value)
                        arr.delete_at(idx+1)
                        return true
                    end
                end

                if prv # absorb TENs/UNITs to the LEFT
                    if prv.has_rank?(TEN, UNIT)
                        @value = self.shift_up(prv.value)
                        arr.delete_at(idx-1)
                        return true
                    end
                end
            end
            super
        end
    end

    class Ten < Token

        # reduce arr by modifying arr; return TRUE if changes made
        def reduce!(arr, idx,level=1)
            nxt = arr[idx+1]
            if nxt
                case level
                when 1 # absorb UNITs to the RIGHT
                    if nxt.has_rank?(UNIT) && ((@value % 10)==0)
                        @value += nxt.value
                        arr.delete_at(idx+1)
                        return true
                    end
                when 2 # absorb TENs to the RIGHT
                    if nxt.has_rank? TEN
                        @value = @value * 100 + nxt.value
                        arr.delete_at(idx+1)
                        return true
                    end
                end
            end
            super
        end
    end

    class Hundred < Token
        # reduce arr by modifying arr; return TRUE if changes made
        def reduce!(arr, idx,level=1)
            nxt = arr[idx+1]
            prv = (idx > 0) ? arr[idx-1] : nil
            case level
            when 1 # absorb UNITs/TENs to the LEFT
                if prv
                    if prv.has_rank?(TEN, UNIT)
                        @value = prv.value * 100
                        arr.delete_at(idx-1)
                        return true
                    end
                end
                if nxt # absorb TENs/UNITs to the RIGHT
                    if nxt.has_rank?(TEN, UNIT)
                        @value = @value + nxt.value
                        arr.delete_at(idx+1)
                        return true
                    end
                end
            end
            super
        end
    end

    class Shift < Token
        # reduce arr by modifying arr; return TRUE if changes made
        def reduce!(arr, idx,level=1)
            nxt = arr[idx+1]
            prv = (idx > 0) ? arr[idx-1] : nil
            case level
            when 1 # absorb UNITs/TENs/HUNDREDS to the LEFT
                if prv
                    if prv.has_rank?(HUNDRED, TEN, UNIT)
                        @value = prv.value * @rank
                        arr.delete_at(idx-1)
                        return true
                    end
                end
            end
            super
        end
    end

    class Suffix < Token
        def initialize(name, value)
            super
            # clear a Suffix operator's rank so that it doesn't participate
            # in any reductions as we build our way up to hundreds
            @rank = nil
        end
        
        # reduce arr by modifying arr; return TRUE if changes made
        def reduce!(arr, idx,level=1)
            nxt = arr[idx+1]
            prv = (idx > 0) ? arr[idx-1] : nil
            case level
            when 1 # absorb UNITs/TENs/HUNDREDS to the LEFT (but not other SUFFIXes)
                if prv
                    unless prv.is_a?(Verbatim) || prv.is_a?(Suffix)
                        @value = @value * prv.value 
                        arr.delete_at(idx-1)
                        return true
                    end
                end
            end
            super
        end
    end

    class Verbatim < Token
        def reduce!(arr, idx, level=1)
            nxt = arr[idx+1]
            case level
            when 1 # at level 1 we do nothing
                false
            when 2 # at level 2 we concatenate adjacent tokens
                if nxt && nxt.is_a?(Verbatim)
                    @value = "#{@value} #{nxt.value}"
                    arr.delete_at(idx+1)
                    return true
                end
            when 99
                arr[idx] = @value # participate in collation
            end
            false
        end
    end

    # Numeric literals, eg "123", "213,456"
    # we treat literals as composed UNITs, i.e. "123" is equivalent
    # to "one two three"
    class Literal < Unit
        def initialize(separator)
            @name = "literal"
            @separator = separator
            @regex = %r{[0-9#{separator}]+}
        end

        # literals don't acquire a value until they are matched
        def match(s)
            if m = @regex.match(s)
                tmp = s.gsub(@separator, '')
                @value = tmp.to_i
                @rank = UNIT
                true
            end
        end
    end

    # the following options are recognised:
    # scale: SHORT for short-scale billions (etc, default) LONG for long-scale
    # merge: true to merge adjacent string literals (default), false to leave them as separate words
    # cockney: true to include the cockney counting system! (default)
    # separator: thousands separator for integer literals e.g. "1000,000,000" (default = ',')
    def initialize(opts={})
        opts[:scale] ||= SHORT
        opts[:merge] ||= true
        opts[:cockney] ||= true
        opts[:separator] ||= ','
        opts[:conjunctions] ||= ['and', ',', ';']

        @debug = false
        @parsers = []
        @split = %r{(?:\b\s*(?:#{opts[:conjunctions].join('|')}|\s+)\s*\b)+}
        
        [ ["one", 1], ["a", 1], ["an", 1], 
          ["two", 2], ["three", 3], ["four", 4], ["five", 5], ["six", 6], ["seven", 7], ["eight", 8], ["nine", 9], ["niner", 9],
          ["zero", 0], ["oh", 0], ["nought", 0], ["ten", 10],
          ["eleven", 11], ["twelve", 12], ["thirteen", 13], ["fourteen", 14], ["fifteen", 15],
          ["sixteen", 16], ["seventeen", 17], ["eighteen", 18], ["nineteen", 19],
        ].each do |x|
            @parsers << Unit.new(*x)
        end

        [ ["twenty", 20], ["thirty", 30], ["forty", 40], ["fifty", 50], ["sixty", 60], ["seventy", 70], ["eighty", 80], ["ninety", 90]
        ].each do |x|
            @parsers << Ten.new(*x)
        end

        @parsers << Hundred.new("hundred", 100)

        if opts[:scale] == SHORT
            [ ["thousand", 1000], ["million", 1e6], ["milliard", 1e9], ["billion", 1e9], ["trillion", 1e12], ["quadrillion", 1e15],
              ["quintillion", 1e18], ["sextillion", 1e21], ["septillion", 1e24], ["octillion", 1e27],
              ["nonillion", 1e30], ["decillion", 1e33]
            ].each do |x|
                @parsers << Shift.new(*x)
            end
        else
            [ ["thousand", 1000], ["million", 1e6], ["milliard", 1e9], ["billion", 1e12], ["trillion", 1e18], ["quadrillion", 1e24],
              ["quintillion", 1e30], ["sextillion", 1e36], ["septillion", 1e42], ["octillion", 1e48],
              ["nonillion", 1e54], ["decillion", 1e60]
            ].each do |x|
                @parsers << Shift.new(*x)
            end
        end

        [ ["dozen", 12], ["score", 20]
        ].each do |x|
            @parsers << Suffix.new(*x)
        end

        if opts[:cockney]
            [ ["lady", 5], ["ladies", 5], ["jackson", 5], ["jacksons", 5], 
              ["tenner", 10], ["tenners", 10], ["ayrton", 10], ["ayrtons", 10],
              ["pony", 25], ["ponies", 25], 
              ["bullseye", 50], ["bullseyes", 50], ["nifty", 50], ["niftie", 50], ["nifties", 50], ["niftys", 50],
              ["ton", 100], ["tonne", 100], ["century", 100], ["centuries", 100], 
              ["monkey", 500], ["monkies", 500],
              ["grand", 1000], ["large", 1000],
              ["archer", 2000], ["archers", 2000],
              ["bernie", 1e6], ["bernies", 1e6]
            ].each do |x|
                @parsers << Suffix.new(*x)
            end
        end

        # sort 'em, longest match first
        @parsers.sort! {|a,b| b.name.length <=> a.name.length}

        # include integer literals at head of list
        @parsers.unshift Literal.new(',')
    end

    # return a list of tokens
    def tokenise(s)
        words = s.split(@split)
        words.map! do |word|
            p = @parsers.find {|p| p.match(word) }
            p ? p.dup : Verbatim.new("verbatim", word)
        end
    end

    # reduce an array of tokens by calling the tokens' reduce functions,
    # but only if the token belongs to class 'klass'
    def reduce!(a, klass, level=1)
        iter = a.each_with_index
        loop do
            begin
                tok,idx = iter.next
                puts "A: #{a} TOK: #{tok} IDX:#{idx}" if @debug
                if tok.is_a? klass
                    iter.rewind if tok.reduce!(a, idx, level) # a modified
                end
            rescue StopIteration
                break
            end
        end
    end

    def parse_dbg(s)
        puts a = tokenise(s)
        puts "TENS LEVEL 1"
        puts reduce!(a, Ten, 1)    # thirty one -> 31
        puts "UNITS LEVEL 1"
        puts reduce!(a, Unit, 1)   # one two three -> 123
        puts "TENS LEVEL 2"
        puts reduce!(a, Ten, 2)    # twenty twelve -> 2012
        puts "UNITS LEVEL 2"
        puts reduce!(a, Unit, 2)   # UNIT/TEN/UNIT/TEN... 2030 123 -> 2030123, 123 2030 -> 1232030
        puts "HUNDREDS LEVEL 1"
        puts reduce!(a, Hundred, 1) # 2 100 -> 200; 100 36 -> 136
        puts "SHIFTS LEVEL 1"
        puts reduce!(a, Shift, 1)   # 55 1000 -> 55000
        puts "SUFFIXES LEVEL 1"
        puts reduce!(a, Suffix, 1) # three score => 60
        puts "VERBATIMS LEVEL 2"      # optional concatenation of adjacent verbatims
        puts reduce!(a, Verbatim, 2)
        puts "COLLATION LEVEL 99"
        puts reduce!(a, Token, 99)      # add adjacent terms
        puts "FINAL #{a}"
        a
    end

    def parse(s)
        return parse_dbg(s) if @debug
        a = tokenise(s)
        reduce!(a, Ten, 1)    # thirty one -> 31
        reduce!(a, Unit, 1)   # one two three -> 123
        reduce!(a, Ten, 2)    # twenty twelve -> 2012
        reduce!(a, Unit, 2)   # UNIT/TEN/UNIT/TEN... 2030 123 -> 2030123, 123 2030 -> 1232030
        reduce!(a, Hundred, 1) # 2 100 -> 200; 100 36 -> 136
        reduce!(a, Shift, 1)   # 55 1000 -> 55000
        reduce!(a, Suffix, 1) # three score => 60
        reduce!(a, Verbatim, 2)
        reduce!(a, Token, 99)      # add adjacent terms
        a
    end
end

if __FILE__ == $0
    require 'expectations'

    np = NumberParser.new
    lnp = NumberParser.new(scale: NumberParser::LONG)

    Expectations do

        # simples
        expect(np.parse("one")) == [1]
        expect(np.parse("two")) == [2]
        expect(np.parse("three")) == [3]

        expect(np.parse("eleven")) == [11]
        expect(np.parse("twelve")) == [12]
        expect(np.parse("thirteen")) == [13]

        expect(np.parse("twenty")) == [20]
        expect(np.parse("pony")) == [25]
        expect(np.parse("thirty")) == [30]
        expect(np.parse("forty")) == [40]

        #complexes
        expect(np.parse("hundred")) == [100]
        expect(np.parse("thousand")) == [1000]
        expect(np.parse("million")) == [1000000]
        expect(np.parse("billion")) == [1000000000]
        expect(lnp.parse("billion"))  == [1000000000000]
        expect(np.parse("trillion")) == [1000000000000]
        expect(lnp.parse("trillion"))  == [1000000000000000000]

        # simple compound
        expect(np.parse("twenty one")) == [21]
        expect(np.parse("forty two")) == [42]

        expect(np.parse("a hundred")) == [100]
        expect(np.parse("a hundred and six")) == [106]
        expect(np.parse("two hundred")) == [200]
        expect(np.parse("five hundred six")) == [506]
        expect(np.parse("five hundred and six")) == [506]
        expect(np.parse("a hundred and six")) == [106]

        # complex compound
        expect(np.parse("five thousand four hundred twenty six")) == [5426]
        expect(np.parse("five thousand four hundred and twenty six")) == [5426]
        expect(np.parse("five thousand, four hundred and twenty six")) == [5426]

        expect(np.parse("five hundred and thirteen thousand, four hundred and twenty six")) == [513426]
        expect(np.parse("five hundred and thirteen thousand four hundred and twenty six")) == [513426]
        expect(np.parse("five hundred thirteen thousand four hundred twenty six")) == [513426]
        expect(np.parse("two hundred and sixty seven thousand, seven hundred and nine")) == [267709] # to one against, and falling...
        expect(np.parse("two hundred sixty seven thousand, seven hundred nine")) == [267709] 
        expect(np.parse("two hundred sixty seven thousand seven hundred nine")) == [267709] 
        expect(np.parse("eight hundred and twenty six million, five hundred and thirteen thousand, four hundred and twenty six")) == [826513426]
        expect(np.parse("eight hundred and twenty six million five hundred and thirteen thousand four hundred and twenty six")) == [826513426]
        expect(np.parse("eight hundred twenty six million five hundred thirteen thousand four hundred twenty six")) == [826513426]

        # simple enumeration style "one two three" => 123
        expect(np.parse("one two")) == [12]
        expect(np.parse("one two three")) == [123]
        expect(np.parse("twenty twelve")) == [2012]
        expect(np.parse("one twenty")) == [120]
        expect(np.parse("twelve hundred")) == [1200]
        expect(np.parse("one twenty hundred")) == [12000] # bit unnatural

        # integer literals
        expect(np.parse("123")) == [123]
        expect(np.parse("123 456")) == [123456]
        expect(np.parse("123 four five six")) == [123456]
        expect(np.parse("one 2 three 4 five 6")) == [123456]
        expect(np.parse("1 two 3 four 5 six")) == [123456]
        expect(np.parse("123 hundred")) == [12300]

        # canonical names
        expect(np.parse("two twenty")) == [220]
        expect(np.parse("two score")) == [40]
        expect(np.parse("five twelve")) == [512]
        expect(np.parse("five dozen")) == [60]

        # cockney
        expect(np.parse("three grand two monkies and a pony")) == [4025]
        expect(np.parse("two large")) == [2000]
        expect(np.parse("a pony")) == [25]
        expect(np.parse("two ponies")) == [50]
        expect(np.parse("a monkey")) == [500]
        expect(np.parse("two monkies")) == [1000]
        expect(np.parse("two nifties")) == [100]
        expect(np.parse("a score")) == [20]
        expect(np.parse("two score")) == [40]
        expect(np.parse("a tenner")) == [10]
        expect(np.parse("three tenners")) == [30]
        expect(np.parse("a bernie")) == [1000000]
        expect(np.parse("a bernie and three archers")) == [1006000]
        expect(np.parse("a bernie, three archers, and a monkey")) == [1006500]
        expect(np.parse("a bernie, three archers and a grand, and a monkey")) == [1007500]
        expect(np.parse("a bernie, three archers and a grand, and a monkey, and a nifty")) == [1007550]
        expect(np.parse("a bernie, three archers and a grand, a monkey and two nifties")) == [1007600]
        expect(np.parse("a bernie, three archers and a grand, a monkey two nifties, and a pony")) == [1007625]
        expect(np.parse("a bernie, three archers and a grand, a monkey two nifties, a pony a tenner and a jackson")) == [1007640]
        
        # test replacements
        expect(np.parse("twenty pence")) == [20, "pence"]
        expect(np.parse("twenty divided by thirty")) == [20, "divided by", 30]
        
    end
end

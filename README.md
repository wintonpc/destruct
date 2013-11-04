# destructure

Destructuring bind is an operation typically found in functional programming languages.
Think of it as regular expressions for data structures.

Consider the following regexp example:

    v = 'madlibs are fun to do'
    if v =~ /madlibs are (?<adjective>\w+) to (?<verb>\w+)/
      puts $~[:adjective]                            # => fun
      puts $~[:verb]                                 # => do
    end

The `=~` operator performs two tasks simultaneously

1. tells us whether `v` matches the regexp pattern
2. binds names to substrings of `v` (if the match succeeded)

With `destructure`, you can pattern match data structures in ruby.

regexp:

         something =~ /pattern/

destructure:

        something =~-> {pattern}

# Example usage

### nested arrays
    v = [5,[6,7],8]
    v =~-> { [a,[b,c],d] }
    puts a                                         # => 5
    puts b                                         # => 6
    puts c                                         # => 7
    puts d                                         # => 8

### plus, it tells us if the match succeeded
    v = [1,2]
    puts (v =~-> { [a, b] }).inspect               # => #<OpenStruct a=1, b=2>
    puts (v =~-> { [a, b, c] }).inspect            # => nil

### hashes
    v = { x: 1, y: 2 }
    v =~-> { { x: a, y: b } }
    puts a                                         # => 1
    puts b                                         # => 2

### order doesn't matter. the pattern specifies a subset that must match
    v = { q: 5, r: 9, t: 42, u: 99 }
    v =~-> { { u: a, r: b } }
    puts a                                         # => 99
    puts b                                         # => 9

### bind to the hash key names, for simplicity
    v =~-> { Hash[q, r, t, u] }
    puts q.inspect                                 # => 5
    puts r.inspect                                 # => 9
    puts t.inspect                                 # => 42
    puts u.inspect                                 # => 99

### objects

    class Widget
      attr_accessor :flange, :sprocket

      def initialize(flange, sprocket)
        @flange, @sprocket = flange, sprocket
      end
    end

### work similarly to a hash
    v = Widget.new('gibble', 8)
    v =~-> { Object[flange: a, sprocket: b] }
    puts a                                         # => gibble
    puts b                                         # => 8

### bind to the attribute names, for simplicity
    v =~-> { Object[flange, sprocket] }
    puts flange                                    # => gibble
    puts sprocket                                  # => 8

### lock down the acceptable type
    match_result = v =~-> { OpenStruct[flange, sprocket] }
    puts match_result.inspect                      # => nil

### pattern attributes must be present, else match fails
    match_result = v =~-> { Object[flange, sprocket, whizz] }
    puts match_result.inspect                      # => nil

### it subsumes built-in functionality:

### regexes
    v = [1, 2, 'hello, bob']
    v =~-> { [a, b, /hello, (?<name>\w+)/] }
    puts a                                         # => 1
    puts b                                         # => 2
    puts name                                      # => bob

### splatting
    v = [1,2,3,4,5,6,7,8,9]
    v =~-> { [1, 2, ~stuff, 9] }                   # '~' indicates a splat
    puts stuff.inspect                             # => [3, 4, 5, 6, 7, 8]

### pattern variables can be pretty much anything that goes on the left hand side of an assignment
    v = [1,4,9]
    v =~-> { [1, @my_var, 9] }
    puts @my_var                                   # => 4

    basket = {}
    v = [1,4,9]
    v =~-> { [1, basket[:thing_i_found], 9] }
    puts basket[:thing_i_found]                    # => 4

    one = OpenStruct.new
    one.two = OpenStruct.new
    v = [17,19,23]
    v =~-> { [17, one.two.three, 23] }
    puts one.two.three                             # => 19

### use '!' to match the value of an expression rather than bind the expression
    y = 3
    puts ([1, 2, 3] =~-> { [1, 2, !y] }).inspect   # => #<OpenStruct>
    puts ([1, 2, 4] =~-> { [1, 2, !y] }).inspect   # => nil
    puts ([1, 2, 4] =~-> { [1, 2, y] }).inspect    # => #<OpenStruct y=4>
    @my_var = 789
    puts (789 =~-> { !@my_var }).inspect           # => #<OpenStruct>
    puts (456 =~-> { !@my_var }).inspect           # => nil
    puts (456 =~-> { @my_var }).inspect            # => #<OpenStruct @my_var=456>

### specify the same variable multiple times in the pattern to require those parts to match
    puts ([1,2,3] =~-> { [x,2,x] }).inspect        # => nil
    puts ([1,2,1] =~-> { [x,2,x] }).inspect        # => #<OpenStruct x=1>

### use wildcards (underscore) when you require a value but otherwise don't care about it
    puts ([1, 2, 'ack!$&@'] =~-> { [1, 2, _] }).inspect # => #<OpenStruct>
    puts ([1, 2, 'ack!$&@'] =~-> { [1, 2, 3] }).inspect # => nil

### you can specify alternative patterns, like in regexes
    puts (:foo =~-> { :foo | :bar }).inspect       # => #<OpenStruct>
    puts (:bar =~-> { :foo | :bar }).inspect       # => #<OpenStruct>
    puts (:baz =~-> { :foo | :bar }).inspect       # => nil

### bind a variable while continuing to match substructure
    v = ['hello', 'starting']
    v =~-> { [ greeting = String, participle = /(?<verb>.*)ing$/ ] }
    puts greeting                                  # => hello
    puts participle                                # => starting
    puts verb                                      # => start

    v = [:not_a_string, 'starting']
    puts (v =~-> { [ greeting = String, participle = /(?<verb>.*)ing$/ ] }).inspect # => nil
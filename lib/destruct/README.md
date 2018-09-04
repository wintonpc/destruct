# Destructure

Destructuring assignment is a powerful capability provided in some programming
languages that simultaneously matches a data structure pattern and extracts
parts of the structure.

You are probably already familiar with the similar capability provided by
regexes.

```rb

```

We can devise a similar pattern-matching language in Ruby.

```rb
pattern = [1, Var.new(:n), 3]
match(pattern, [1, 2, 3])   # => {n: 2}
match(pattern, [1, 4, 3])   # => {n: 4}
match(pattern, [1, 2, 4])   # => nil
match(pattern, [1, 2])   # => nil
```

A larger example:

```rb
# example with splats, object matches, etc.
```

Unfortunately, the more power we add, the more verbosity creeps up, which
negates the main benefit of destructuring assignment: making the code appear
similar to the data being matched, which aids understanding.

What would really be nice is if we had a pattern matching DSL.

Ruby Procs contain valid but otherwise arbitrary ruby syntax. Since they never
need to be executed, we can treat them as syntax containers. We can obtain
this syntax and impart our own semantics.

To make this work, we need a function that translates ruby syntax into a
pattern. The translator iteratively applies a set of rules to the input syntax
to produce the output pattern.

A rule consists of a pattern and a transformer proc. The pattern matches input
syntax and the proc transforms the matched syntax into a corresponding output
pattern.






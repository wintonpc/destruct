# destruct

Destructuring assignment in Ruby

General REPL usage:
```rb
# bundle exec irb
>> require 'destruct_repl'
=> true
>> p([1, Var.new(:x)]).match([1, 2])
=> #<Env: x=2>
>> transform(ast { [1, x] }).match([1, 2])
=> #<Env: x=2>
```

Show code:
```rb
cpat = compile([1, Var.new(:x)])
cpat.show_code
```

Show transformations:
```rb
$show_transformations = true
transform(ast { [1, v, 3 | 4] })
```

- `types.rb` - pattern matchers
- `standard_pattern.rb` - invented syntax for pattern matchers
- `destruct_spec.rb` - example case/when usage.

If you get a "No method 'eval' on NilClass" error or "binding must be provided" error,
pass `binding` to any methods that take it as an optional parameter:

```rb
Point = Struct.new(:x, :y)
transform(ast { Point[x: 1, y: v] }, binding)
```


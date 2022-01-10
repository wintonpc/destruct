require "rspec"
require "destruct/expr_cache"
require "destruct_ext"
require "unparser"

def define_syntax(name, &transformer)
  define_method(name) do |&block|
    expr_in = Destruct::ExprCache.get(block)
    expr_out = transformer.(expr_in)
    code = Unparser.unparse(expr_out)
    eval(code, block.binding)
  end
end

define_syntax :foo do |x|
  x
end

describe "rds" do
  it "works" do
    x = 1
    y = 2
    result = foo { x + y }
    puts result
  end
end

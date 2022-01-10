require "rspec"
require "destruct/expr_cache"
require "destruct_ext"

def define_syntax(name, &transformer)
  define_method(name) do |&block|
    transformer.(Destruct::ExprCache.get(block))
  end
end

define_syntax :foo do |x|
  x
end

describe "rds" do
  it "works" do
    result = foo do
      x + y
    end
    puts result
  end
end

require "rspec"
require "destruct/expr_cache"
require "destruct_ext"
require "unparser"
require "binding_of_caller"

def syntax(&block)
  Destruct::ExprCache.get(block)
end

def quasisyntax(&block)
  do_unsyntax(Destruct::ExprCache.get(block), block.binding)
end

def do_unsyntax(x, b)
  if x.is_a?(Parser::AST::Node)
    if x.type == :send && x.children[0].nil? && x.children[1] == :unsyntax
      with_eval_snippet(unp(x.children[2])) do
        eval($eval_snippet, b, "$eval_snippet")
      end
    else
      Parser::AST::Node.new(x.type, x.children.map { |c| do_unsyntax(c, b) })
    end
  else
    x
  end
end

def with_eval_snippet(s)
  old = $eval_snippet
  $eval_snippet = s
  yield
ensure
  $eval_snippet = old
end

def define_syntax(name, &transformer)
  define_method(name) do |*args, &block|
    expr_out = transformer.(args, block && syntax(&block))
    code = Unparser.unparse(expr_out)
    eval(code, block ? block.binding : binding.of_caller(1))
  end
end

define_syntax :foo do |_, x|
  x
end

define_syntax :bar do |args|
  quasisyntax { unsyntax { args } + 1 }
end

describe "rds" do
  it "works" do
    x = 1
    y = 2
    expect(foo { x + y }).to be 3
    # expect(bar 5).to be 6
  end
  it "syntax" do
    expect(unp(syntax{ a + 1 })).to eql "a + 1"
  end
  it "quasisyntax" do
    sa = syntax { a }
    expect(unp(quasisyntax { unsyntax(sa) + 1 })).to eql "a + 1"
    expect(unp(quasisyntax { unsyntax(syntax { a }) + 1 })).to eql "a + 1"
    # expect(quasisyntax { unsyntax(a) + 1 }).to eql "a + 1"
  end
end

def unp(x)
  Unparser.unparse(x)
end

def node_to_array(x)
  if x.is_a?(Parser::AST::Node)
    node_to_array([x.type, *x.children])
  elsif x.is_a?(Array)
    x.map { |x| node_to_array(x) }
  else
    x
  end
end

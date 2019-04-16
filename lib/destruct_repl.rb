require_relative './destruct'

def ast(pat_proc=nil, &pat_block)
  Destruct::ExprCache.get(pat_proc || pat_block)
end

def transform(node, binding=nil)
  pat = Destruct::RuleSets::StandardPattern.transform(node, binding: binding)
  Destruct::Pattern.new(pat)
end

def compile(pat)
  if pat.is_a?(Destruct::Pattern)
    pat = pat.pat
  end
  Destruct::Compiler.compile(pat)
end

def dmatch(pat_or_proc, x, binding=nil)
  pat = pat_or_proc.is_a?(Proc) ? transform(ast(pat_or_proc)) : pat_or_proc
  compile(pat).match(x, binding)
end

def p(pat)
  Destruct::Pattern.new(pat)
end

Var = Destruct::Var
Splat = Destruct::Splat
Or = Destruct::Or
Let = Destruct::Let
Unquote = Destruct::Unquote
Obj = Destruct::Obj

puts <<~EOD
def ast(pat_proc=nil, &pat_block)
def transform(node)
def compile(pat)
def match(pat_or_proc, x)
def p(pat)
EOD

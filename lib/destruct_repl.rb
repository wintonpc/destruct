require_relative './destruct'

def ast(pat_proc=nil, &pat_block)
  Destruct::ExprCache.get(pat_proc || pat_block)
end

def transform(node, binding=nil)
  Destruct::RuleSets::StandardPattern.transform(node, binding: binding)
end

def compile(pat)
  Destruct::Compiler.compile(pat)
end

def match(pat_or_proc, x, binding=nil)
  pat = pat_or_proc.is_a?(Proc) ? transform(ast(pat_or_proc)) : pat_or_proc
  compile(pat).match(x, binding)
end

puts <<~EOD
def ast(pat_proc=nil, &pat_block)
def transform(node)
def compile(pat)
def match(pat_or_proc, x)
EOD

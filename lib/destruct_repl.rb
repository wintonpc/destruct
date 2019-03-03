require_relative './destruct'

def ast(&block)
  Destruct::ExprCache.get(block)
end

def transform(node, binding: nil)
  Destruct::RuleSets::StandardPattern.transform(node, binding: binding)
end

def compile(pat)
  Destruct::Compiler.compile(pat)
end

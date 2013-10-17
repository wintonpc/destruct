require 'sourcify'
require 'decons'

def pmatch(x, &pat_block)
  sp = pat_block.to_sexp.to_a.last
  pat = transform(sp)
  Decons::match(pat, x).to_openstruct
end

def transform(sp)
  _ = Decons::_
  case
    when e = rmatch([:call, _, var(:name), _], sp); var(e[:name])
    when e = rmatch([:lit, var(:value)], sp); e[:value]
    when e = rmatch([:true], sp); true
    when e = rmatch([:false], sp); false
    when e = rmatch([:nil], sp); nil
    when e = rmatch([:str, var(:s)], sp); e[:s]
    when e = rmatch([:array, splat(:items)], sp); e[:items].map(&method(:transform))
    when e = rmatch([:hash, splat(:kvs)], sp); Hash[*e[:kvs].map(&method(:transform))]
    else; raise "Unexpected sexp: #{sp.inspect}"
  end
end

private ########################################

def rmatch(*args)
  Decons::match(*args)
end

def var(name)
  Var.new(name)
end

def splat(name)
  Splat.new(name)
end

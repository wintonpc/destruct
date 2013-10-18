require 'sourcify'
require 'active_support/inflector'
require 'decons'

def pmatch(x, &pat_block)
  sp = pat_block.to_sexp.to_a.last
  pat = transform(sp)
  Decons::match(pat, x).to_openstruct
end

def transform(sp)
  _ = Decons::_
  klass_sym = Var.new(&method(:is_constant?))
  case
    when e = rmatch([:const, klass_sym], sp)
      make_obj(e[klass_sym], [])
    when e = rmatch([:call, _, klass_sym, [:arglist, [:hash, splat(:kv_sexps)]]], sp)
      kvs = transform_many(e[:kv_sexps])
      make_obj(e[klass_sym], Hash[*kvs])
    when e = rmatch([:call, _, klass_sym, [:arglist, splat(:field_name_sexps)]], sp)
      field_names = transform_many(e[:field_name_sexps])
      make_obj(e[klass_sym], Hash[field_names.map { |f| [f.name, var(f.name)] }])
    when e = rmatch([:call, _, var(:name), _], sp); var(e[:name])
    when e = rmatch([:lit, var(:value)], sp); e[:value]
    when e = rmatch([:true], sp); true
    when e = rmatch([:false], sp); false
    when e = rmatch([:nil], sp); nil
    when e = rmatch([:str, var(:s)], sp); e[:s]
    when e = rmatch([:array, splat(:items)], sp); e[:items].map(&method(:transform))
    when e = rmatch([:hash, splat(:kvs)], sp); Hash[*e[:kvs].map(&method(:transform))]
    when e = rmatch([:cvar, var(:name)], sp); splat(e[:name].to_s.sub(/^@@/, '').to_sym)
    else; raise "Unexpected sexp: #{sp.inspect}"
  end
end

private ########################################

def transform_many(xs)
  xs.map(&method(:transform))
end

def make_obj(klass_sym, field_map)
  Obj.of_type(klass_sym.to_s.constantize, field_map)
end

def is_constant?(x)
  x.is_a?(Symbol) && is_uppercase?(x.to_s[0])
end

def is_uppercase?(char)
  char == char.upcase
end

def rmatch(*args)
  Decons::match(*args)
end

def var(name)
  Var.new(name)
end

def splat(name)
  Splat.new(name)
end

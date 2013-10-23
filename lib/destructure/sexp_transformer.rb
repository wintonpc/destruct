require 'destructure/dmatch'

module Destructure
  class SexpTransformer

    def self.transform(sp)
      SexpTransformer.new.transform(sp)
    end

    def transform(sp)
      _ = DMatch::_
      klass_sym = DMatch::Var.new(&method(:is_constant?))
      case
        when e = dmatch([:call, _, :_, _], sp); _
        when e = dmatch([:const, klass_sym], sp)
          make_obj(e[klass_sym], {})
        when e = dmatch([:call, _, klass_sym, [:arglist, [:hash, splat(:kv_sexps)]]], sp)
          kvs = transform_many(e[:kv_sexps])
          make_obj(e[klass_sym], Hash[*kvs])
        when e = dmatch([:call, _, klass_sym, [:arglist, splat(:field_name_sexps)]], sp)
          field_names = transform_many(e[:field_name_sexps])
          make_obj(e[klass_sym], Hash[field_names.map { |f| [f.name, var(f.name)] }])
        when e = dmatch([:call, _, var(:name), _], sp); var(e[:name])
        when e = dmatch([:lit, var(:value)], sp); e[:value]
        when e = dmatch([:true], sp); true
        when e = dmatch([:false], sp); false
        when e = dmatch([:nil], sp); nil
        when e = dmatch([:str, var(:s)], sp); e[:s]
        when e = dmatch([:array, splat(:items)], sp); e[:items].map(&method(:transform))
        when e = dmatch([:hash, splat(:kvs)], sp); Hash[*e[:kvs].map(&method(:transform))]
        when e = dmatch([:cvar, var(:name)], sp); splat(e[:name].to_s.sub(/^@@/, '').to_sym)
        else; raise "Unexpected sexp: #{sp.inspect}"
      end
    end

    private ########################################

    def transform_many(xs)
      xs.map(&method(:transform))
    end

    def make_obj(klass_sym, field_map)
      DMatch::Obj.of_type(klass_sym.to_s.constantize, field_map)
    end

    def is_constant?(x)
      x.is_a?(Symbol) && is_uppercase?(x.to_s[0])
    end

    def is_uppercase?(char)
      char == char.upcase
    end

    def dmatch(*args)
      DMatch::match(*args)
    end

    def var(name)
      DMatch::Var.new(name)
    end

    def splat(name)
      DMatch::Splat.new(name)
    end
  end
end
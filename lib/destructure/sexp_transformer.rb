require 'active_support/inflector'
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
        # plain object type
        when e = dmatch([:const, klass_sym], sp)
          make_obj(e[klass_sym], {})
        # generic call
        when e = dmatch([:call, var(:receiver), var(:msg), var(:arglist)], sp)
          transform_call(e[:receiver], e[:msg], e[:arglist])
        # instance variable
        when e = dmatch([:ivar, var(:name)], sp); var(e[:name])
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

    def transform_call(*sexp_call)
      sexp_receiver, sexp_msg, sexp_args = sexp_call
      _ = DMatch::_
      klass_sym_var = DMatch::Var.new(&method(:is_constant?))
      case
        # Class[...]
        when e = dmatch([[:const, klass_sym_var], :[]], [sexp_receiver, sexp_msg]); transform_obj_matcher(e[klass_sym_var], sexp_args)
        # local variable
        when e = dmatch([nil, var(:name), [:arglist]], sexp_call); var(e[:name])
        # call chain (@one.two(12).three[3].four)
        when e = dmatch([var(:receiver), var(:msg), [:arglist]], sexp_call); var(unwind_lhs(e[:receiver], e[:msg]))
        else; nil
      end
    end

    def transform_obj_matcher(klass_sym, sexp_args)
      case
        # Class[a: 1, b: 2]
        when e = dmatch([:arglist, [:hash, splat(:kv_sexps)]], sexp_args)
          kvs = transform_many(e[:kv_sexps])
          make_obj(klass_sym, Hash[*kvs])
        # Class[a, b, c]
        when e = dmatch([:arglist, splat(:field_name_sexps)], sexp_args)
          field_names = transform_many(e[:field_name_sexps])
          make_obj(klass_sym, Hash[field_names.map { |f| [f.name, var(f.name)] }])
      end
    end

    def unwind_lhs(receiver, msg)
      unwind_receivers(receiver).gsub(/\.\[/, '[') + msg.to_s
    end

    def unwind_receivers(receiver)
      case
        when receiver.nil?; ''
        when e = dmatch([:ivar, var(:name)], receiver); "#{e[:name]}."
        when e = dmatch([:call, var(:receiver), :[], [:arglist, splat(:args)]], receiver)
          unwind_receivers(e[:receiver]) + "[#{transform_many(e[:args]).map{|x| x.to_s}.join(', ')}].".gsub(/\(\)$/, '')
        when e = dmatch([:call, var(:receiver), var(:msg), [:arglist, splat(:args)]], receiver)
          unwind_receivers(e[:receiver]) + "#{e[:msg]}(#{transform_many(e[:args]).map{|x| x.to_s}.join(', ')})".gsub(/\(\)$/, '') + '.'
        else; raise 'oops'
      end
    end

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
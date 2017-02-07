require 'active_support/inflector'
require 'destructure/dmatch'

module Destructure
  class SexpTransformer

    def self.transform(sp, caller_binding)
      SexpTransformer.new(caller_binding).transform(sp)
    end

    def initialize(caller_binding)
      @caller_binding = caller_binding
    end

    def transform(sp)
      _ = DMatch::_
      klass_sym = DMatch::Var.new(&method(:is_constant?))
      case

        # '_' (wildcard)
      when e = dmatch([:call, _, :_, _], sp); _

        # object matcher without parameters
      when e = dmatch([:const, klass_sym], sp)
        make_obj(e[klass_sym], {})

        # namespace-qualified object matcher without parameters
      when e = dmatch([:colon2, splat(:args)], sp)
        make_obj(read_fq_const(sp), {})

        # '~' (splat)
      when e = dmatch([:call, var(:identifier_sexp), :~, [:arglist]], sp); splat(unwind_receivers_and_clean(e[:identifier_sexp]))

        # '!' (variable value)
      when e = dmatch([:not, var(:value_sexp)], sp)
        @caller_binding.eval(unwind_receivers_and_clean(e[:value_sexp]).to_s)

        # '|' (alternative patterns)
      when e = dmatch([:call, var(:rest), :|, [:arglist, var(:alt)]], sp); DMatch::Or.new(*[e[:rest], e[:alt]].map(&method(:transform)))

        # generic call
      when e = dmatch([:call, var(:receiver), var(:msg), var(:arglist)], sp)
        transform_call(e[:receiver], e[:msg], e[:arglist])

        # instance variable
      when e = dmatch([:ivar, var(:name)], sp); var(e[:name].to_s)

        # let
        # ... with local or instance vars
      when e = dmatch([DMatch::Or.new(:lasgn, :iasgn), var(:lhs), var(:rhs)], sp)
        let_var(e[:lhs], transform(e[:rhs]))

        # ... with attributes or something more complicated
      when e = dmatch([:attrasgn, var(:obj), var(:attr), [:arglist, var(:rhs)]], sp)
        var_name = unwind_receivers_and_clean([:call, e[:obj], e[:attr].to_s.sub(/=$/,'').to_sym, [:arglist]])
        let_var(var_name, transform(e[:rhs]))

        # literal values
      when e = dmatch([:lit, var(:value)], sp); e[:value]
      when e = dmatch([:true], sp); true
      when e = dmatch([:false], sp); false
      when e = dmatch([:nil], sp); nil
      when e = dmatch([:str, var(:s)], sp); e[:s]
      when e = dmatch([:array, splat(:items)], sp); e[:items].map(&method(:transform))
      when e = dmatch([:hash, splat(:kvs)], sp); Hash[*e[:kvs].map(&method(:transform))]
      else; raise "Unexpected sexp: #{sp.inspect}"
      end
    end

    private ########################################

    def read_fq_const(sp, parts=[])
      klass_sym = DMatch::Var.new(&method(:is_constant?))
      case
      when e = dmatch([:const, klass_sym], sp)
        parts = [e[klass_sym]] + parts
        Object.const_get("#{parts.join('::')}")
      when e = dmatch([:colon2, var(:prefix), var(:last)], sp)
        read_fq_const(e[:prefix], [e[:last]] + parts)
      end
    end

    def transform_call(*sexp_call)
      sexp_receiver, sexp_msg, sexp_args = sexp_call
      _ = DMatch::_
      klass_sym_var = DMatch::Var.new(&method(:is_constant?))
      case
        # Class[...]
      when e = dmatch([[:const, klass_sym_var], :[]], [sexp_receiver, sexp_msg])
        field_map = make_field_map(sexp_args)
        klass_sym = e[klass_sym_var]
        klass_sym == :Hash ? field_map : make_obj(klass_sym, field_map)

        # namespace-qualified constant receiver
      when e = dmatch([:colon2, splat(:args)], sexp_receiver)
        field_map = make_field_map(sexp_args)
        klass_sym = read_fq_const(sexp_receiver)
        make_obj(klass_sym, field_map)

        # local variable
      when e = dmatch([nil, var(:name), [:arglist]], sexp_call)
        var(e[:name])

        # call chain (@one.two(12).three[3].four)
      else
        var(unwind_receivers_and_clean([:call, *sexp_call]))
      end
    end

    def make_field_map(sexp_args)
      case
        # Class[a: 1, b: 2]
      when e = dmatch([:arglist, [:hash, splat(:kv_sexps)]], sexp_args)
        kvs = transform_many(e[:kv_sexps])
        Hash[*kvs]

        # Class[a, b, c]
      when e = dmatch([:arglist, splat(:field_name_sexps)], sexp_args)
        field_names = transform_many(e[:field_name_sexps])
        Hash[field_names.map { |f| [f.name, var(f.name)] }]
      else; raise 'oops'
      end
    end

    def unwind_receivers_and_clean(receiver)
      unwound = unwind_receivers(receiver).gsub(/\.$/, '').gsub(/\.\[/, '[')
      identifier?(unwound) ? unwound.to_sym : unwound
    end

    def identifier?(x)
      x =~ /^[_a-zA-Z][_0-9a-zA-Z]*$/
    end

    def unwind_receivers(receiver)
      case
      when receiver.nil?; ''
      when e = dmatch([:lit, var(:value)], receiver); "#{e[:value]}."
      when e = dmatch([:ivar, var(:name)], receiver); "#{e[:name]}."
      when e = dmatch([:call, var(:receiver), :[], [:arglist, splat(:args)]], receiver)
        unwind_receivers(e[:receiver]) + format_hash_call(e[:args])
      when e = dmatch([:call, var(:receiver), var(:msg), [:arglist, splat(:args)]], receiver)
        unwind_receivers(e[:receiver]) + format_method_call(e[:msg], e[:args])
      else; raise 'oops'
      end
    end

    def format_method_call(msg, args)
      "#{msg}(#{transform_args(args)})".gsub(/\(\)$/, '') + '.'
    end

    def format_hash_call(args)
      "[#{transform_args(args)}].".gsub(/\(\)$/, '')
    end

    def transform_args(args)
      transform_many(args).map { |x| x.is_a?(Symbol) ? ":#{x}" : x.to_s }.join(', ')
    end

    def transform_many(xs)
      xs.map(&method(:transform))
    end

    def make_obj(klass_sym, field_map)
      DMatch::Obj.of_type(klass_sym.to_s.constantize, field_map)
    end

    def is_constant?(x, env=nil)
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

    def let_var(name, pattern)
      DMatch::Var.new(name) { |x, env| DMatch.new(env).match(pattern, x) }
    end

    def splat(name)
      DMatch::Splat.new(name)
    end
  end
end

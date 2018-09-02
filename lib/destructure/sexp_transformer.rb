# frozen_string_literal: true

require 'active_support/inflector'
require 'destructure/dmatch'

class Proc
  def cached_source_location
    @cached_source_location ||= source_location # don't allocate a new array every time
  end
end

class DMatch
  class SexpTransformer
    class << self
      def transform(p)
        p_src = p.cached_source_location
        patterns_by_proc.fetch(p_src) do
          patterns_by_proc[p_src] = ProcSexps.get(p) do |sexp|
            Pattern.from(SexpTransformer.new(p.binding).transform(sexp))
          end
        end
      end

      def patterns_by_proc
        Thread.current[:st_patterns_by_proc] ||= {}
      end
    end

    attr_reader :caller_binding

    def initialize(caller_binding)
      @caller_binding = caller_binding
    end

    def transform(sp)
      _ = DMatch::_
      klass_sym = Var.new(&method(:is_constant?))
      case

        # '_' wildcard
      when e = dmatch([:send, _, :_], sp)
        _

        # object matcher without parameters
      when e = dmatch([:const, var(:parent), klass_sym], sp)
        make_obj(flatten_nested_constants(e[:parent], e[klass_sym]), {})

        # namespace-qualified object matcher without parameters
      when e = dmatch([:colon2, splat(:args)], sp) # TODO: unused?
        make_obj(read_fq_const(sp), {})

        # '~' (splat)
      when e = dmatch([:send, var(:identifier_sexp), :~], sp)
        splat(unwind_receivers_and_clean(e[:identifier_sexp]))

        # '!' (variable value)
      when e = dmatch([:send, var(:value_sexp), :!], sp)
        Ref.new(unwind_receivers_and_clean(e[:value_sexp]).to_s)

        # '|' (alternative patterns)
      when e = dmatch([:send, var(:rest), :|, var(:alt)], sp)
        Or.new(*[e[:rest], e[:alt]].map(&method(:transform)))

        # let with local or instance vars
      when e = dmatch([Or.new(:lvasgn, :ivasgn), var(:lhs), var(:rhs)], sp)
        let_var(e[:lhs], transform(e[:rhs]))

        # let with attributes or something more complicated
      when e = dmatch([:send, var(:obj), /(?<attr>[^=]+)=/, var(:rhs)], sp)
        var_name = unwind_receivers_and_clean([:send, e[:obj], e[:attr].sub(/=$/,'').to_sym])
        let_var(var_name, transform(e[:rhs]))

        # generic call
      when e = dmatch([:send, var(:receiver), var(:msg), splat(:arglist)], sp)
        transform_call(e[:receiver], e[:msg], e[:arglist])

        # instance variable
      when e = dmatch([:ivar, var(:name)], sp)
        var(e[:name].to_s)

        # local variable
      when e = dmatch([:lvar, var(:name)], sp)
        var(e[:name])

        # literal values
      when e = dmatch([a_literal, var(:value)], sp); e[:value]
      when e = dmatch([:true], sp); true
      when e = dmatch([:false], sp); false
      when e = dmatch([:nil], sp); nil
      when e = dmatch([:regexp, [:str, var(:str)], [:regopt, splat(:opts)]], sp)
        Regexp.new(e[:str], map_regexp_opts(e[:opts]))
      when e = dmatch([:array, splat(:items)], sp)
        e[:items].map(&method(:transform))
      when e = dmatch([:hash, splat(:pairs)], sp)
        transform_pairs(e[:pairs])
      else
        raise InvalidPattern.new(sp)
      end
    end

    private

    def flatten_nested_constants(parent_sexp, child_str)
      klass_sym = Var.new(&method(:is_constant?))
      case
      when e = dmatch(nil, parent_sexp)
        child_str
      when e = dmatch([:cbase], parent_sexp)
        "::#{child_str}"
      when e = dmatch([:const, var(:parent), klass_sym], parent_sexp)
        "#{flatten_nested_constants(e[:parent], e[klass_sym])}::#{child_str}"
      else
        raise InvalidPattern.new(parent_sexp)
      end
    end

    def transform_pairs(pairs)
      pairs.map do |p|
        ep = dmatch([:pair, var(:k), var(:v)], p)
        [transform(ep[:k]), transform(ep[:v])]
      end.to_h
    end

    def map_regexp_opts(syms)
      opts = 0
      opts |= Regexp::IGNORECASE if syms.include?(:i)
      opts |= Regexp::MULTILINE if syms.include?(:m)
      opts |= Regexp::EXTENDED if syms.include?(:x)
      opts
    end

    def read_fq_const(sp, parts=[])
      klass_sym = Var.new(&method(:is_constant?))
      case
      when e = dmatch([:const, nil, klass_sym], sp)
        parts = [e[klass_sym]] + parts
        Object.const_get("#{parts.join('::')}")
      when e = dmatch([:colon2, var(:prefix), var(:last)], sp)
        read_fq_const(e[:prefix], [e[:last]] + parts)
      end
    end

    def transform_call(*sexp_call)
      sexp_receiver, sexp_msg, sexp_args = sexp_call
      _ = DMatch::_
      klass_sym_var = Var.new(&method(:is_constant?))
      case
        # Class[...]
      when e = dmatch([[:const, nil, klass_sym_var], :[]], [sexp_receiver, sexp_msg])
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
        var(unwind_receivers_and_clean([:send, sexp_receiver, sexp_msg, *sexp_args]))
      end
    end

    def make_field_map(sexp_args)
      case
        # Class[a: 1, b: 2]
      when e = dmatch([[:hash, splat(:pairs)]], sexp_args)
        transform_pairs(e[:pairs])

        # Class[a, b, c]
      when e = dmatch([splat(:field_name_sexps)], sexp_args)
        field_names = transform_many(e[:field_name_sexps])
        Hash[field_names.map { |f| [f.name, var(f.name)] }]
      else
        raise InvalidPattern.new(sexp_args)
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
      when e = dmatch([a_literal, var(:value)], receiver); "#{e[:value]}."
      when e = dmatch([:ivar, var(:name)], receiver); "#{e[:name]}."
      when e = dmatch([:lvar, var(:name)], receiver); "#{e[:name]}."
      when e = dmatch([:send, var(:receiver), :[], splat(:args)], receiver)
        unwind_receivers(e[:receiver]) + format_hash_call(e[:args])
      when e = dmatch([:send, var(:receiver), var(:msg), splat(:args)], receiver)
        unwind_receivers(e[:receiver]) + format_method_call(e[:msg], e[:args])
      else
        raise InvalidPattern.new(receiver)
      end
    end

    def a_literal
      Or.new(:int, :float, :str, :sym)
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
      Obj.of_type(klass_sym.to_s.constantize, field_map)
    end

    def is_constant?(x, env=nil)
      x.is_a?(Symbol) && is_uppercase?(x.to_s[0])
    end

    def is_uppercase?(char)
      char == char.upcase
    end

    def dmatch(*args)
      DMatch.match(*args)
    end

    def var(name)
      Var.new(name)
    end

    def let_var(name, pattern)
      Var.new(name) { |x, env| DMatch.new(env).match(pattern, x) }
    end

    def splat(name)
      Splat.new(name)
    end
  end

  class InvalidPattern < StandardError
    attr_reader :pattern

    def initialize(bad_pattern, unparsed=nil)
      super(unparsed ? "Code: #{unparsed.inspect}\nAST:  #{bad_pattern.inspect}" : bad_pattern.inspect)
      @pattern = bad_pattern
    end
  end
end

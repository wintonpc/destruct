# frozen_string_literal: true

require 'active_support/inflector'
require 'destructure/dmatch'

class DMatch
  class SexpTransformer0
    class << self
      def transform(p)
        p_src = p.source_location
        patterns_by_proc.fetch(p_src) do
          patterns_by_proc[p_src] = SexpTransformer0.new(p.binding).transform(ProcSexps.get(p))
        end
      end

      def patterns_by_proc
        Thread.current[:st0_patterns_by_proc] ||= {}
      end
    end

    def initialize(caller_binding)
      @caller_binding = caller_binding
    end

    def transform(sp)
      _ = DMatch::_
      case

        # '_' (wildcard)
      when e = dmatch([:send, _, :_], sp)
        _

        # '~' (splat)
      when e = dmatch([:send, [:send, nil, let_var(:name, Obj.of_type(Symbol))], :~], sp)
        splat(e[:name])

        # '|' (alternative patterns)
      when e = dmatch([:send, var(:rest), :|, var(:alt)], sp)
        Or.new(*[e[:rest], e[:alt]].map(&method(:transform)))

        # let
        # ... with local or instance vars
      when e = dmatch([Or.new(:lvasgn, :ivasgn), var(:lhs), var(:rhs)], sp)
        let_var(e[:lhs], transform(e[:rhs]))

        # call (as local varialbe)
      when e = dmatch([:send, nil, var(:name)], sp)
        var(e[:name])

        # literal values
      when e = dmatch([Or.new(:int, :float, :str, :sym), var(:value)], sp); e[:value]
      when e = dmatch([:nil], sp); nil
      when e = dmatch([:regexp, [:str, var(:str)], _], sp)
        Regexp.new(e[:str])
      when e = dmatch([:array, splat(:items)], sp)
        e[:items].map(&method(:transform))
      else; raise "Unexpected sexp: #{sp.inspect}"
      end
    end

    private

    def dmatch(*args)
      DMatch.match(*args)
    end

    def var(name)
      Var.new(name)
    end

    def let_var(name, pattern)
      Var.new(name) { |x, env| DMatch.new(env: env).match(pattern, x) }
    end

    def splat(name)
      Splat.new(name)
    end
  end
end

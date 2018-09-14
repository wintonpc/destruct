class Destruct
  module RuleSets
    module Helpers
      def n(type, children=[])
        Obj.new(Parser::AST::Node, type: type, children: children)
      end

      def v(name)
        Var.new(name)
      end

      def s(name)
        Splat.new(name)
      end

      def any(*alt_patterns)
        Or.new(*alt_patterns)
      end
    end
  end
end

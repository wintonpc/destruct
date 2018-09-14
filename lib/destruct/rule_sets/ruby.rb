# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'

class Destruct
  module RuleSets
    class Ruby
      include RuleSet
      include Helpers

      def initialize
        add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
        add_rule(n(:nil, [])) { nil }
        add_rule(n(:true, [])) { true }
        add_rule(n(:false, [])) { false }
        add_rule(n(:array, v(:items))) { |items:| items }
        add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
        add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
        add_rule(n(:lvar, [v(:name)])) { |name:| VarRef.new(name) }
        add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
        add_rule(n(:const, [v(:parent), v(:name)]), parent: [ConstRef, NilClass]) { |parent:, name:| ConstRef.new([parent&.fqn, name].compact.join("::")) }
        add_rule(n(:cbase)) { ConstRef.new("") }
      end

      class VarRef
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_s
          "#<VarRef: #{name}>"
        end
        alias_method :inspect, :to_s
      end

      class ConstRef
        attr_reader :fqn

        def initialize(fqn)
          @fqn = fqn
        end

        def to_s
          "#<ConstRef: #{fqn}>"
        end
        alias_method :inspect, :to_s
      end

      # def m(type, *children)
      #   ::Parser::AST::Node.new(type, children)
      # end
      #
      # RubyInverse = Transformer.from(Identity) do
      #   add_rule(Integer) { |value| m(:int, value) }
      #   add_rule(Symbol) { |value| m(:sym, value) }
      #   add_rule(Float) { |value| m(:float, value) }
      #   add_rule(String) { |value| m(:str, value) }
      #   add_rule(nil) { m(:nil) }
      #   # add_rule(n(:true, [])) { true }
      #   # add_rule(n(:false, [])) { false }
      #   # add_rule(n(:array, v(:items))) { |items:| items }
      #   # add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
      #   # add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
      #   # add_rule(n(:lvar, [v(:name)])) { |name:| VarRef.new(name) }
      #   # add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
      #   # add_rule(n(:const, [v(:parent), v(:name)]), parent: ConstRef) { |parent:, name:| ConstRef.new([parent&.fqn, name].compact.join("::")) }
      #   # add_rule(n(:cbase)) { ConstRef.new("") }
      # end
    end
  end
end

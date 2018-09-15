# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'

class Destruct
  module RuleSets
    class UnpackEnumerables
      include RuleSet
      include Helpers

      def initialize
        add_rule(Array) { |a, transform:| a.map { |v| transform.(v) } }
        add_rule(Hash) { |h, transform:| h.map { |k, v| [transform.(k), transform.(v)] }.to_h }
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
    end
  end
end

class Object
  def transformer_eql?(other)
    self == other
  end
end

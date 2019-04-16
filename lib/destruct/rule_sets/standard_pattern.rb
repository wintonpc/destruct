# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'

class Destruct
  module RuleSets
    class StandardPattern
      include RuleSet

      def initialize
        meta_rule_set AstToPattern
        add_rule(->{ strict(pat) }) { |pat:| Strict.new(pat) }
        add_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
        add_rule(->{ !expr }) { |expr:| Unquote.new(Transformer.unparse(expr)) }
        add_rule(->{ name = pat }, name: Symbol) { |name:, pat:| Let.new(name, pat) }
        add_rule(-> { a | b }) { |a:, b:| Or.new(a, b) }
        add_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: [Var]) do |klass:, field_pats:|
          Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
        end
        add_rule(->{ klass[field_pats] }, klass: [Class, Module], field_pats: Hash) do |klass:, field_pats:|
          Obj.new(klass, field_pats)
        end
        add_rule(->{ is_a?(klass) }, klass: [Class, Module]) { |klass:| Obj.new(klass) }
        add_rule(->{ v }, v: [Var, Ruby::VarRef]) do |v:|
          raise Transformer::NotApplicable unless v.name == :_
          Any
        end
        add_rule_set(PatternBase)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end

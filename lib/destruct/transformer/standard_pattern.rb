# frozen_string_literal: true

require_relative './pattern_base'

class Destruct
  class Transformer
    StandardPattern = Transformer.from(PatternBase) do
      add_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
      add_rule(->{ !expr }) { |expr:| Unquote.new(unparse(expr)) }
      add_rule(->{ name = pat }, name: Symbol) { |name:, pat:| Let.new(name, pat) }
      add_rule(-> { a | b }) { |a:, b:| Or.new(a, b) }
      add_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: Var) do |klass:, field_pats:|
        Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
      end
      add_rule(->{ klass[field_pats] }, klass: [Class, Module], field_pats: Hash) do |klass:, field_pats:|
        Obj.new(klass, field_pats)
      end
      add_rule(->{ v }, v: [Var, VarRef]) do |v:|
        raise Transformer::NotApplicable unless v.name == :_
        Any
      end
    end
  end
end

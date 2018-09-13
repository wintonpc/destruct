# frozen_string_literal: true

require_relative './pattern_base'

class Destruct
  class Transformer
    StandardPattern = Transformer.from(PatternBase) do
      add_rule(->{ ~v }, v: Var) { |v:| Splat.new(v.name) }
      add_rule(->{ klass[*field_pats] }, klass: [Class, Module], field_pats: Var) do |klass:, field_pats:|
        Obj.new(klass, field_pats.map { |f| [f.name, f] }.to_h)
      end
      add_rule(->{ klass[field_pats] }, klass: [Class, Module], field_pats: Hash) do |klass:, field_pats:|
        Obj.new(klass, field_pats)
      end
    end
  end
end

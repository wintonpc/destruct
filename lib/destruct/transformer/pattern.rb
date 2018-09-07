require_relative './ruby'

class Destruct
  class Transformer
    Pattern = Transformer.from(Ruby) do
      add_rule(VarRef) { |ref| Var.new(ref.name) }
    end
  end
end

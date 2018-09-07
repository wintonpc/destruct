require_relative './ruby'

class Destruct
  class Transformer
    Destruct = Transformer.from(Ruby) do
      add_rule(VarRef) { |ref| Var.new(ref.name) }
      add_rule(ConstRef) { |ref, binding:| binding.eval(ref.fqn) }
    end
  end
end

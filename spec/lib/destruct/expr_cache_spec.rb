# frozen_string_literal: true

require 'destruct'

class Destruct
  describe ExprCache do
    it 'caches proc expressions' do
      p = proc { 1 + 2 }
      expr = ExprCache.get(p)
      expect(expr).to be_a Parser::AST::Node
      expect(expr.type).to eql :send

      expr_again = ExprCache.get(p)
      expect(expr_again).to eql expr
    end
  end
end

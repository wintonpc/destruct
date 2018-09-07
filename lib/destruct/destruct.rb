require 'unparser'
require 'destruct/transformer/destruct'

class Destruct
  class << self
    def destruct(obj, &block)
      case_stx = Transformer::Destruct.transform(tag_unmatched: false, &block)
      clauses = case_stx.whens.map do |w|
        [Compiler.compile(w.pred), Unparser.unparse(w.body)]
      end.to_h
      clauses
    end
  end
end

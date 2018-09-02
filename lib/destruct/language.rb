

# frozen_string_literal: true

class Destruct
  class Language
    LITERAL_TYPES = %i[int sym float str].freeze

    def translate(&pat_proc)
      expr = ExprCache.get(pat_proc)
      if !expr.is_a?(Parser::AST::Node)
        expr
      elsif LITERAL_TYPES.include?(expr.type)
        expr.children[0]
      else
        raise "No translation rule for #{expr}"
      end
    end
  end
end

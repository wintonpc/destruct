class Destruct
  class << self
    def destruct(&block)
      case_stx = Transformer::PatternBase.transform(&block)
      cpatterns = case_stx.whens.map(&:pred).map { |pat| Compiler.compile(pat) }
      cpatterns
    end
  end
end

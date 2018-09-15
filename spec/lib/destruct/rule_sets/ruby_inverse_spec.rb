require 'destruct'

class Destruct
  describe RuleSets::RubyInverse do
    it 'nil' do
      n = tx(nil)
      expect(n.type).to eql :nil
    end
    it 'literals' do
      n = tx(1)
      expect(n.type).to eql :int
      expect(n.children).to eql [1]

      n = tx(:foo)
      expect(n.type).to eql :sym
      expect(n.children).to eql [:foo]

      n = tx(1.0)
      expect(n.type).to eql :float
      expect(n.children).to eql [1.0]

      n = tx("foo")
      expect(n.type).to eql :str
      expect(n.children).to eql ["foo"]
    end

    def tx(pat)
      r = RuleSets::RubyInverse.transform(pat)
      expect(r).to be_a Parser::AST::Node
      r
    end
  end
end

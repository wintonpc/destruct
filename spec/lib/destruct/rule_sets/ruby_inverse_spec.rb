require 'destruct'

class Destruct
  describe RuleSets::RubyInverse do
    it 'transforms ruby AST nodes to ruby objects' do
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

      n = tx(nil)
      expect(n.type).to eql :nil

      n = tx(true)
      expect(n.type).to eql :true

      n = tx(false)
      expect(n.type).to eql :false

      n = tx([1, 2])
      expect(n.type).to eql :array
      expect(n.children.map(&:type)).to eql [:int, :int]
    end

    def tx(pat)
      r = RuleSets::RubyInverse.transform(pat)
      expect(r).to be_a Parser::AST::Node
      r
    end
  end
end

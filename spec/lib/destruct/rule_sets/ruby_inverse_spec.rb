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
      expect(n.children.map { |c| c.children[0] }).to eql [1, 2]

      n = tx({a: 1, b: 2})
      expect(n.type).to eql :hash
      expect(n.children.map(&:type)).to eql [:pair, :pair]
      expect(n.children.map { |c| c.children[0].children[0] }).to eql [:a, :b]
      expect(n.children.map { |c| c.children[1].children[0] }).to eql [1, 2]

      n = tx(RuleSets)
      expect(n.type).to eql :const
      expect(n.children[1]).to eql :RuleSets
      base = n.children[0]
      expect(n.type).to eql :const
      expect(base.children[1]).to eql :Destruct
      base = base.children[0]
      expect(base.type).to eql :cbase
    end

    def tx(pat)
      r = RuleSets::RubyInverse.transform(pat)
      expect(r).to be_a Parser::AST::Node
      r
    end
  end
end

require 'destruct'

class Destruct
  describe Compiler do
    it 'compiles literals' do
      cp = Compiler.compile(1)
      expect(cp.match(1)).to be_truthy
      expect(cp.match(2)).to be_falsey

      cp = Compiler.compile("foo")
      expect(cp.match("foo")).to be_truthy
      expect(cp.match("bar")).to be_falsey
    end
    it 'compiles vars' do
      cp = Compiler.compile(Var.new(:foo))
      e = cp.match(1)
      expect(e).to be_an Env
      expect(e[:foo]).to eql 1
    end
    it 'compiles plain objs' do
      cp = Compiler.compile(Obj.new(Hash))
      expect(cp.match({})).to be_truthy
      expect(cp.match([])).to be_falsey
    end
    Foo = Struct.new(:a, :b)
    it 'compiles objs with field patterns' do
      cp = Compiler.compile(Obj.new(Foo, a: 1, b: 2))
      expect(cp.match([])).to be_falsey
      expect(cp.match(Foo.new(1, 2))).to be_truthy
      expect(cp.match(Foo.new(1, 3))).to be_falsey
    end
    it 'compiles objs with vars' do
      cp = Compiler.compile(Obj.new(Foo, a: 1, b: Var.new(:bvar)))
      e = cp.match(Foo.new(1, 2))
      expect(e).to be_an Env
      expect(e[:bvar]).to eql 2
    end
    it 'compiles objs with deep vars' do
      cp = Compiler.compile(Obj.new(Foo, a: 1, b: Obj.new(Foo, a: 1, b: Var.new(:bvar))))
      e = cp.match(Foo.new(1, Foo.new(1, 2)))
      expect(e).to be_an Env
      expect(e[:bvar]).to eql 2
    end
    it 'compiles ORs' do
      cp = Compiler.compile(Or.new(1, 2))
      # expect(cp.match(1)).to be_truthy
      expect(cp.match(2)).to be_truthy
      # expect(cp.match(3)).to be_nil
    end
    it 'compiles deep ORs' do
      cp = Compiler.compile(Or.new(Obj.new(Foo, a: 1), Obj.new(Foo, a: 2)))
      expect(cp.match(Foo.new(1))).to be_truthy
      expect(cp.match(Foo.new(2))).to be_truthy
      expect(cp.match(Foo.new(3))).to be_nil
    end
    it 'compiles nested ORs' do
      cp = Compiler.compile(Or.new(Obj.new(Foo, a: 1), Obj.new(Foo, a: Or.new(2, 3))))
      expect(cp.match(Foo.new(1))).to be_truthy
      expect(cp.match(Foo.new(2))).to be_truthy
      expect(cp.match(Foo.new(3))).to be_truthy
      expect(cp.match(Foo.new(4))).to be_nil
    end
    it 'compiles arrays' do
      cp = Compiler.compile([1, Var.new(:foo)])
      e = cp.match([1, 2])
      expect(e).to be_an Env
      expect(e[:foo]).to eql 2
      expect(cp.match([2, 2])).to be_falsey
      expect(cp.match([])).to be_falsey
      expect(cp.match([1, 2, 3])).to be_falsey
    end
  end
end

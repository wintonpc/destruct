require 'destruct'

class Destruct
  describe Compiler do
    it 'compiles literals' do
      cp = Compiler.compile(1)
      expect(cp.match(1)).to be_a Env
      expect(cp.match(2)).to be_nil

      cp = Compiler.compile("foo")
      expect(cp.match("foo")).to be_a Env
      expect(cp.match("bar")).to be_nil
    end
    it 'compiles vars' do
      cp = Compiler.compile(Var.new(:foo))
      e = cp.match(1)
      expect(e).to be_an Env
      expect(e[:foo]).to eql 1
    end
    it 'compiles objs' do
      cp = Compiler.compile(Obj.new(Hash))
      expect(cp.match({})).to be_a Env
      expect(cp.match([])).to be_nil
    end
    Foo = Struct.new(:a, :b)
    it 'compiles objs with field patterns' do
      cp = Compiler.compile(Obj.new(Foo, a: 1, b: 2))
      expect(cp.match([])).to be_nil
      expect(cp.match(Foo.new(1, 2))).to be_a Env
      expect(cp.match(Foo.new(1, 3))).to be_nil
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
      expect(cp.match(1)).to be_a Env
      expect(cp.match(2)).to be_a Env
      expect(cp.match(3)).to be_nil
    end
  end
end

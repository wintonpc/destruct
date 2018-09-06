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

      cp = Compiler.compile([Var.new(:foo), Var.new(:bar)])
      e = cp.match([1, 2])
      expect(e).to be_an Env
      expect(e[:foo]).to eql 1
      expect(e[:bar]).to eql 2
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
      expect(cp.match(1)).to be_truthy
      expect(cp.match(2)).to be_truthy
      expect(cp.match(3)).to be_nil
    end
    it 'compiles deep ORs' do
      cp = Compiler.compile(Or.new(Obj.new(Foo, a: 1), Obj.new(Foo, a: 2)))
      expect(cp.match(Foo.new(1))).to be_truthy
      expect(cp.match(Foo.new(2))).to be_truthy
      expect(cp.match(Foo.new(3))).to be_nil
    end
    it 'compiles ORs with arrays' do
      cp = Compiler.compile(Or.new(Obj.new(Foo, a: [1, 2, 3]), Obj.new(Foo, a: 4)))
      expect(cp.match(Foo.new(4))).to be_truthy
    end
    it 'compiles nested ORs' do
      cp = Compiler.compile(Or.new(Obj.new(Foo, a: 9, b: 1), Obj.new(Foo, a: 9, b: Or.new(2, 3))))
      expect(cp.match(Foo.new(9, 1))).to be_truthy
      expect(cp.match(Foo.new(9, 2))).to be_truthy
      expect(cp.match(Foo.new(9, 3))).to be_truthy
      expect(cp.match(Foo.new(9, 4))).to be_nil
    end
    it 'compiles nested ORs with Vars' do
      cp = Compiler.compile(Or.new(Obj.new(Foo, a: 1), Obj.new(Foo, a: Or.new(2, 3), b: Var.new(:x))))
      expect(cp.match(Foo.new(2, 9))[:x]).to eql 9
    end
    it 'compiles arrays' do
      cp = Compiler.compile([1, Var.new(:foo)])
      e = cp.match([1, 2])
      expect(e).to be_an Env
      expect(e[:foo]).to eql 2
      expect(cp.match([2, 2])).to be_falsey
      expect(cp.match([])).to be_falsey
      expect(cp.match([1, 2, 3])).to be_falsey
      expect(cp.match(Object.new)).to be_falsey
    end
    it 'array edge cases' do
      expect(Compiler.compile([]).match([])).to be_truthy
      expect(Compiler.compile([1]).match([2])).to be_falsey
      expect(Compiler.compile([1]).match([1, 2])).to be_falsey
      expect(Compiler.compile([1]).match([8, 9])).to be_falsey
      expect(Compiler.compile([1, 2]).match([1])).to be_falsey
      expect(Compiler.compile([8, 9]).match([1])).to be_falsey
      expect(Compiler.compile([1, 2]).match([1, 2])).to be_truthy
      expect(Compiler.compile([1, 2]).match([8, 9])).to be_falsey
    end
    it 'compiles nested arrays' do
      cp = Compiler.compile([1, [2, [3, 4], 5], 6, 7])
      expect(cp.match([1, [2, [3, 4], 5], 6, 7])).to be_truthy
    end
    it 'compiles splats' do
      # splat in middle
      expect(Compiler.compile([1, Splat.new(:x), 4]).match([1, 2, 3, 4])[:x]).to eql [2, 3]
      expect(Compiler.compile([1, Splat.new(:x), 4]).match([1, 2, 4])[:x]).to eql [2]
      expect(Compiler.compile([1, Splat.new(:x), 4]).match([1, 4])[:x]).to eql []
      expect(Compiler.compile([1, Splat.new(:x), 4]).match([1])).to be_falsey

      # splat at front
      expect(Compiler.compile([Splat.new(:x), 3]).match([1, 2, 3])[:x]).to eql [1, 2]
      expect(Compiler.compile([Splat.new(:x), 3]).match([1, 3])[:x]).to eql [1]
      expect(Compiler.compile([Splat.new(:x), 3]).match([3])[:x]).to eql []
      expect(Compiler.compile([Splat.new(:x), 3]).match([])).to be_falsey

      # splat at end
      expect(Compiler.compile([1, Splat.new(:x)]).match([1, 2, 3])[:x]).to eql [2, 3]
      expect(Compiler.compile([1, Splat.new(:x)]).match([1, 2])[:x]).to eql [2]
      expect(Compiler.compile([1, Splat.new(:x)]).match([1])[:x]).to eql []
      expect(Compiler.compile([1, Splat.new(:x)]).match([])).to be_falsey
    end
    it 'compiles open-ended splat with enumerable' do
      en = (1..3).cycle
      e = Compiler.compile([Var.new(:head), Splat.new(:tail)]).match(en)
      expect(e[:head]).to eql 1
      expect(e[:tail].take(3).to_a).to eql [2, 3, 1]

      # doesn't reevaluate
      evaluations = []
      tail = Enumerator.new do |y|
        i = 0
        while true
          evaluations << i
          y << i
          i += 1
        end
      end
      head_and_tail = Compiler.compile([Var.new(:head), Splat.new(:tail)])
      e = head_and_tail.match(tail)
      expect(e[:head]).to eql 0
      e = head_and_tail.match(e[:tail])
      expect(e[:head]).to eql 1
      e = head_and_tail.match(e[:tail])
      expect(e[:head]).to eql 2
      expect(evaluations).to eql [0, 1, 2]
      expect(e[:tail]).to be_a WrappedEnumerator
      expect(e[:tail].instance_exec { @inner }).to be_an Enumerator
      expect(e[:tail].instance_exec { @inner }).to_not be_a WrappedEnumerator
    end
  end
end

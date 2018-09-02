require 'destructure'

class DMatch
  describe ProcSexps do
    context "proc types" do
      N = Parser::AST::Node
      it 'gets sexp for a proc' do
        [
            proc { 1 + 2 },
            Proc.new { 1 + 2 },
            lambda { 1 + 2 },
            -> { 1 + 2 },
            block_as_proc { 1 + 2 }
        ].each do |p|
          $testing = true
          node = ProcSexps.get(p)
          $testing = false
          # expect(node).to be_a Parser::AST::Node
          # expect(node.type).to eql :send
          # expect(node.children.size).to eql 3 #[:send, [:int, 1], :+, [:int, 2]]
          destructure(node, :or_raise) do
            # match { N[type: :send, children: [N[type: :int, children: [1]], :+, N[type: :int, children: [2]]]] }
            match n(:send, n(:int, 1), :+, n(:int, 2))
          end
        end
      end

      def n(type, *children)
        Obj.of_type(Parser::AST::Node, {type: type, children: children})
      end

      it 'interpolates strings' do
        s = "dynamic"
        p = proc { "a #{s} string" }
        expect(ProcSexps.get(p)).to eq [:str, "a dynamic string"]
      end

      def block_as_proc(&block)
        block
      end
    end
  end
end

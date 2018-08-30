require 'destructure'

class DMatch
  describe ProcSexps do
    context "proc types" do
      it 'gets sexp for a proc' do
        [
            proc { 1 + 2 },
            Proc.new { 1 + 2 },
            lambda { 1 + 2 },
            -> { 1 + 2 },
            block_as_proc { 1 + 2 }
        ].each do |p|
          expect(ProcSexps.get(p)).to eq [:send, [:int, 1], :+, [:int, 2]]
        end
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

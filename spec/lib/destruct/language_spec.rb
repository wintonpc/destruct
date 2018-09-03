# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Language do
    it 'built-in rules' do
      lang = Language.new
      expect(lang.translate { 1 }).to eql 1
      # expect(lang.translate { 2.0 }).to eql 2.0
      # expect(lang.translate { :x }).to eql :x
      # expect(lang.translate { 'x' }).to eql 'x'
      # x_var = lang.translate { x }
      # expect(x_var).to be_a Var
      # expect(x_var.name).to eql :x
    end
    it 'passes matches to the block' do
      lang = Language.new
      lang.add_rule(->{ ~v }) do |v:|
        Splat.new(v.name)
      end
      foo_splat = lang.translate { ~foo }
      expect(foo_splat).to be_a Splat
      expect(foo_splat.name).to eql :foo
    end
  end
end

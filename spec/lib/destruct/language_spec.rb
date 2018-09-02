# frozen_string_literal: true

require 'destruct'

class Destruct
  describe Language do
    it 'has rules' do
      lang = Language.new
      # lang.add_rule(->{ ~v }) do |v:|
      #   Splat.new(v.name)
      # end
      expect(lang.translate { 1 }).to eql 1
      expect(lang.translate { 2.0 }).to eql 2.0
      expect(lang.translate { :x }).to eql :x
      expect(lang.translate { 'x' }).to eql 'x'
    end
  end
end

require 'rspec'
$LOAD_PATH.push File.join(File.dirname(__FILE__), './lib')
require 'decons'

shared_context 'types' do
  Obj = Decons::Obj unless defined? Obj
  Env = Decons::Env unless defined? Env
  Var = Decons::Var unless defined? Var
  Splat = Decons::Splat unless defined? Splat
  FilterSplat = Decons::FilterSplat unless defined? FilterSplat
  SelectSplat = Decons::SelectSplat unless defined? SelectSplat
  Pred = Decons::Pred unless defined? Pred
end


require 'rspec'
$LOAD_PATH.push File.join(File.dirname(__FILE__), './lib')
require 'destruct'

shared_context 'types' do
  Obj = Destruct::Obj unless defined? Obj
  Env = Destruct::Env unless defined? Env
  Var = Destruct::Var unless defined? Var
  Splat = Destruct::Splat unless defined? Splat
  FilterSplat = Destruct::FilterSplat unless defined? FilterSplat
  SelectSplat = Destruct::SelectSplat unless defined? SelectSplat
  Pred = Destruct::Pred unless defined? Pred
end


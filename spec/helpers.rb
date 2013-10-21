require 'rspec'
$LOAD_PATH.push File.join(File.dirname(__FILE__), './lib')
require 'env'
require 'types'

shared_context 'types' do
  Obj = Decons::Obj
  Env = Decons::Env
  Var = Decons::Var
  Splat = Decons::Splat
  Pred = Decons::Pred
end


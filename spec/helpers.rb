require 'rspec'
$LOAD_PATH.push File.join(File.dirname(__FILE__), './lib')
require 'env'
require 'types'

Obj = Decons::Obj
Env = Decons::Env
Var = Decons::Var
Splat = Decons::Splat
Pred = Decons::Pred

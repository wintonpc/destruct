require 'rspec'
$LOAD_PATH.push File.join(File.dirname(__FILE__), '../lib/destructure')
require 'dmatch'

shared_context 'types' do
  Obj = Dmatch::Obj unless defined? Obj
  Env = Dmatch::Env unless defined? Env
  Var = Dmatch::Var unless defined? Var
  Splat = Dmatch::Splat unless defined? Splat
  FilterSplat = Dmatch::FilterSplat unless defined? FilterSplat
  SelectSplat = Dmatch::SelectSplat unless defined? SelectSplat
  Pred = Dmatch::Pred unless defined? Pred
end


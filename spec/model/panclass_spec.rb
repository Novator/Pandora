require 'pandora_helper'

describe Pandora::Model::PandoraClass do
  it "should be true" do
    MyModel.new.the_truth.should be_true
  end
end

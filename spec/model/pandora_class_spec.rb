require 'pandora_helper'


describe Pandora::Model::PandoraClass do

  let!(:fixture_xml) { REXML::Document.new File.open("#{Pandora.root}/spec/fixtures/00-test.xml") }
  let!(:element) {  }

  it "should open fixture xml file before test" do
    expect(fixture_xml).not_to be_nil
  end

  describe ""

end

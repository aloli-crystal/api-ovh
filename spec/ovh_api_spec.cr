require "./spec_helper"

describe OvhApi do
  it "expose une version" do
    OvhApi::VERSION.should eq("0.4.0")
  end

  it "liste les endpoints connus" do
    OvhApi::ENDPOINTS.keys.should contain(:eu)
    OvhApi::ENDPOINTS.keys.should contain(:ca)
    OvhApi::ENDPOINTS.keys.should contain(:us)
  end
end

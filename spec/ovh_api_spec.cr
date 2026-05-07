require "./spec_helper"
require "yaml"

describe OvhApi do
  it "expose une version" do
    yml = YAML.parse(File.read(File.join(__DIR__, "..", "shard.yml")))
    OvhApi::VERSION.should eq(yml["version"].as_s)
  end

  it "liste les endpoints connus" do
    OvhApi::ENDPOINTS.keys.should contain(:eu)
    OvhApi::ENDPOINTS.keys.should contain(:ca)
    OvhApi::ENDPOINTS.keys.should contain(:us)
  end
end

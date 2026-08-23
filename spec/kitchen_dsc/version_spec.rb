# frozen_string_literal: true

RSpec.describe Kitchen::Dsc do
  describe "VERSION" do
    subject(:version) { described_class::VERSION }

    it "is a frozen string" do
      expect(version).to be_a(String).and be_frozen
    end

    it "is a dotted release number" do
      expect(version).to match(/\A\d+\.\d+\.\d+(?:\.[A-Za-z0-9]+)*\z/)
    end

    it "matches the version the gemspec builds against" do
      gemspec = Gem::Specification.load(File.expand_path("../../kitchen-dsc.gemspec", __dir__))

      expect(gemspec.version.to_s).to eq(version)
    end
  end
end

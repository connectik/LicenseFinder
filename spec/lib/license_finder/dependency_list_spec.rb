require 'spec_helper'

describe LicenseFinder::DependencyList do
  def build_gemspec(name, version, dependency=nil)
    Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.summary = 'summary'
      s.description = 'description'

      if dependency
        s.add_dependency dependency
      end
    end
  end

  before do
    config = stub(LicenseFinder).config.stub!
    config.whitelist { [] }
    config.ignore_groups { [] }
  end

  describe '.from_bundler' do
    subject do
      bundle = stub(Bundler::Definition).build.stub!
      bundle.dependencies { [] }
      bundle.groups { [] }
      bundle.specs_for { [build_gemspec('gem1', '1.2.3'), build_gemspec('gem2', '0.4.2')] }

      LicenseFinder::DependencyList.from_bundler
    end

    it "should have 2 dependencies" do
      subject.dependencies.size.should == 2
    end

    it 'should maintain the incoming order' do
      subject.dependencies[0].name.should == 'gem1'
      subject.dependencies[0].version.should == '1.2.3'

      subject.dependencies[1].name.should == 'gem2'
      subject.dependencies[1].version.should == '0.4.2'
    end

    context "when initialized with a parent and child gem" do
      subject do
        bundle = stub(Bundler::Definition).build.stub!
        bundle.dependencies { [] }
        bundle.groups { [] }
        bundle.specs_for { [build_gemspec('gem1', '1.2.3', 'gem2'), build_gemspec('gem2', '0.4.2')] }

        LicenseFinder::DependencyList.from_bundler
      end

      it "should update the child dependency with its parent data" do
        gem1 = subject.dependencies.first
        gem2 = subject.dependencies.last

        gem2.parents.should == [gem1]
      end
    end
  end

  describe '#from_yaml' do
    subject do
      LicenseFinder::DependencyList.from_yaml([
        {'name' => 'gem1', 'version' => '1.2.3', 'license' => 'MIT', 'approved' => false},
        {'name' => 'gem2', 'version' => '0.4.2', 'license' => 'MIT', 'approved' => false}
      ].to_yaml)
    end

    it 'should have 2 dependencies' do
      subject.dependencies.size.should == 2
    end

    it 'should maintain the incoming order' do
      subject.dependencies[0].name.should == 'gem1'
      subject.dependencies[0].version.should == '1.2.3'

      subject.dependencies[1].name.should == 'gem2'
      subject.dependencies[1].version.should == '0.4.2'
    end
  end

  describe '#as_yaml' do
    it "should generate yaml" do
      list = LicenseFinder::DependencyList.new([
        LicenseFinder::Dependency.new('name' => 'b_gem', 'version' => '0.4.2', 'license' => 'MIT', 'approved' => false, 'source' => "bundle"),
        LicenseFinder::Dependency.new('name' => 'a_gem', 'version' => '1.2.3', 'license' => 'MIT', 'approved' => false)
      ])

      list.as_yaml.should == [
        {
          'name' => 'a_gem',
          'version' => '1.2.3',
          'license' => 'MIT',
          'approved' => false,
          'source' => nil,
          'homepage' => nil,
          'license_url' => LicenseFinder::License::MIT.license_url,
          'notes' => '',
          'license_files' => nil,
          'readme_files' => nil
        },
        {
          'name' => 'b_gem',
          'version' => '0.4.2',
          'license' => 'MIT',
          'approved' => false,
          'source' => 'bundle',
          'homepage' => nil,
          'license_url' => LicenseFinder::License::MIT.license_url,
          'notes' => '',
          'license_files' => nil,
          'readme_files' => nil
        }
      ]
    end
  end

  describe '#to_yaml' do
    it "should generate yaml" do
      list = LicenseFinder::DependencyList.new([
        LicenseFinder::Dependency.new('name' => 'b_gem', 'version' => '0.4.2', 'license' => 'MIT', 'approved' => false, 'source' => "bundle"),
        LicenseFinder::Dependency.new('name' => 'a_gem', 'version' => '1.2.3', 'license' => 'MIT', 'approved' => false)
      ])

      yaml = YAML.load(list.to_yaml)
      yaml.should == list.as_yaml
    end
  end

  describe 'round trip' do
    it 'should recreate from to_yaml' do
      list = LicenseFinder::DependencyList.new([
        LicenseFinder::Dependency.new('name' => 'gem1', 'version' => '1.2.3', 'license' => 'MIT', 'approved' => false),
        LicenseFinder::Dependency.new('name' => 'gem2', 'version' => '0.4.2', 'license' => 'MIT', 'approved' => false)
      ])

      new_list = LicenseFinder::DependencyList.from_yaml(list.to_yaml)
      new_list.dependencies.size.should == 2
      new_list.dependencies.first.name.should == 'gem1'
      new_list.dependencies[1].name.should == 'gem2'
    end
  end

  describe '#merge' do
    let(:old_dep) do
      LicenseFinder::Dependency.new(
        'name' => 'foo',
        'version' => '0.0.1',
        'source' => 'bundle'
      )
    end
    let(:old_list) { LicenseFinder::DependencyList.new([old_dep]) }

    let(:new_dep) do
      LicenseFinder::Dependency.new(
        'name' => 'foo',
        'version' => '0.0.2',
        'source' => 'bundle'
      )
    end
    let(:new_list) { LicenseFinder::DependencyList.new([new_dep]) }

    it 'should merge dependencies with the same name' do
      merged_list = old_list.merge(new_list)

      merged_deps = merged_list.dependencies.select { |d| d.name == 'foo' }
      merged_deps.should have(1).item

      merged_dep = merged_deps.first
      merged_dep.name.should == 'foo'
      merged_dep.version.should == '0.0.2'
    end

    it 'should add new dependencies' do
      new_dep.name = 'bar'

      merged_list = old_list.merge(new_list)
      merged_list.dependencies.should include(new_dep)
    end

    it 'should keep dependencies not originating from the bundle' do
      old_dep.source = ''

      merged_list = old_list.merge(new_list)
      merged_list.dependencies.should include(old_dep)
    end

    it 'should remove dependencies missing from the bundle' do
      old_dep.source = 'bundle'

      merged_list = old_list.merge(new_list)
      merged_list.dependencies.should_not include(old_dep)
    end
  end

  describe "#to_s" do
    it "should return a human readable list of dependencies" do

      gem1 = Struct.new(:name, :to_s).new("a", "a string")
      gem2 = Struct.new(:name, :to_s).new("b", "b string")

      list = LicenseFinder::DependencyList.new([gem2, gem1])

      list.to_s.should == "a string\nb string"
    end
  end

  describe '#action_items' do
    it "should return all unapproved dependencies" do
      gem1 = LicenseFinder::Dependency.new('name' => 'a', 'approved' => true)
      stub(gem1).to_s { 'a string' }

      gem2 = LicenseFinder::Dependency.new('name' => 'b', 'approved' => false)
      stub(gem2).to_s { 'b string' }

      gem3 = LicenseFinder::Dependency.new('name' => 'c', 'approved' => false)
      stub(gem3).to_s { 'c string' }

      list = LicenseFinder::DependencyList.new([gem1, gem2, gem3])

      list.action_items.should == "b string\nc string"
    end
  end

  describe '#to_html' do
    it "should concatenate the results of the each dependency's #to_html and plop it into a proper HTML document" do
      gem1 = LicenseFinder::Dependency.new('name' => 'a')
      stub(gem1).to_html { 'A' }

      gem2 = LicenseFinder::Dependency.new('name' => 'b')
      stub(gem2).to_html { 'B' }

      list = LicenseFinder::DependencyList.new([gem1, gem2])

      html = list.to_html
      html.should include "A"
      html.should include "B"
    end
  end
end
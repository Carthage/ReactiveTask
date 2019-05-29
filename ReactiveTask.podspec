Pod::Spec.new do |s|
  s.name         = "ReactiveTask"
  # Version goes here and will be used to access the git tag later on, once we have a first release.
  s.version      = "0.15.1"
  s.summary      = "Swift framework for launching shell tasks"
  s.description  = <<-DESC
                   ReactiveTask is a Swift framework for launching shell tasks (processes), built using ReactiveSwift.
                   DESC
  s.homepage     = "https://github.com/Carthage/ReactiveTask"
  s.license      = { :type => "MIT", :file => "LICENSE.md" }
  s.author       = "Carthage"

  s.platform = :osx
  s.osx.deployment_target = "10.9"

  s.source       = { :git => "https://github.com/Carthage/ReactiveTask.git", :tag => "#{s.version}" }
  # Directory glob for all Swift files
  s.source_files  = "Sources/*.{swift}"
  s.dependency 'Result', '~> 4.1'
  s.dependency 'ReactiveSwift', '~> 5.0'

  s.pod_target_xcconfig = {"OTHER_SWIFT_FLAGS[config=Release]" => "$(inherited) -suppress-warnings" }

  s.cocoapods_version = ">= 1.4.0"
  s.swift_version = "4.2"
end

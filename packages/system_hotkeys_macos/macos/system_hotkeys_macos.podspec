#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint system_hotkeys_macos.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'system_hotkeys_macos'
  s.version          = '0.1.0'
  s.summary          = 'System-wide keyboard shortcuts for Flutter on macOS, through RegisterEventHotKey.'
  s.description      = <<-DESC
System-wide keyboard shortcuts for Flutter on macOS, through RegisterEventHotKey.
                       DESC
  s.homepage         = 'https://github.com/hinata-platform/system_hotkeys'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'hinata-platform' => 'https://github.com/hinata-platform' }

  s.source           = { :path => '.' }
  s.source_files = 'system_hotkeys_macos/Sources/system_hotkeys_macos/**/*.swift'
  s.resource_bundles = {'system_hotkeys_macos_privacy' => ['system_hotkeys_macos/Sources/system_hotkeys_macos/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

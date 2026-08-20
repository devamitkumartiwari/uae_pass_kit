#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint uae_pass_kit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'uae_pass_kit'
  s.version          = '0.0.1'
  s.summary          = 'A complete, unofficial Flutter plugin for UAE Pass.'
  s.description      = <<-DESC
App-to-app sign-in, full profile retrieval, document sharing (proof of
presentation), PDF e-signature, token refresh and logout for UAE Pass,
built in pure Dart with no vendored native binaries.
                       DESC
  s.homepage         = 'https://github.com/uae-pass-kit/uae_pass_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'uae_pass_kit contributors' => 'oss@uaepasskit.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'uae_pass_kit/Sources/uae_pass_kit/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'uae_pass_kit_privacy' => ['uae_pass_kit/Sources/uae_pass_kit/PrivacyInfo.xcprivacy']}
end

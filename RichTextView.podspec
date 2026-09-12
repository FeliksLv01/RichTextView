Pod::Spec.new do |s|
  s.name = 'RichTextView'
  s.version = '0.1.0'
  s.summary = 'A CoreText-based rich text renderer with Markdown support'
  s.description = <<-DESC
    RichTextView provides immutable rich-content models, CoreText layout,
    UIKit rendering, attachments, selection, and Markdown conversion.
  DESC
  s.homepage = 'https://github.com/FeliksLv01/RichTextView'
  s.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author = { 'FeliksLv01' => 'felikslv@163.com' }
  s.source = { :git => 'https://github.com/FeliksLv01/RichTextView.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = 'Sources/**/*.swift'
  s.frameworks = 'CoreGraphics', 'CoreText', 'QuartzCore', 'UIKit'
  s.dependency 'SwiftMarkdownBinary', '0.8.0-patch.1'
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }

  s.test_spec 'Tests' do |tests|
    tests.source_files = 'Tests/RichTextViewTests/**/*.swift'
  end
end

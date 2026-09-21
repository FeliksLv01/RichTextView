Pod::Spec.new do |s|
  s.name = 'RichTextView'
  s.version = '0.1.2'
  s.summary = 'A unified rich-text node-tree renderer for UIKit'
  s.description = <<-DESC
    RichTextView renders an immutable, format-independent rich-text node tree
    with CoreText. It includes UIKit rendering, attachments, interaction,
    selection, and a Markdown-to-node-tree input adapter.
  DESC
  s.homepage = 'https://github.com/FeliksLv01/RichTextView'
  s.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author = { 'FeliksLv01' => 'felikslv@163.com' }
  s.source = { :git => 'https://github.com/FeliksLv01/RichTextView.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.static_framework = true
  s.frameworks = 'CoreGraphics', 'CoreText', 'QuartzCore', 'UIKit'
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.default_subspecs = 'Core'

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/Core/**/*.swift', 'Sources/Rendering/**/*.swift'
    core.resource_bundles = { 'RichTextViewResources' => ['Sources/Resources/**/*'] }
    core.dependency 'RichTextViewTreeSitterBinary', '0.25.10.2'
    core.dependency 'RichTextViewMathBinary', '2.5.0.2'

    core.test_spec 'Tests' do |tests|
      tests.source_files = 'Tests/RichTextViewTests/RichElementSnapshotTests.swift',
                           'Tests/RichTextViewTests/RichTextLayoutEngineTests.swift',
                           'Tests/RichTextViewTests/RichTextViewUsageTests.swift'
    end
  end

  s.subspec 'Markdown' do |markdown|
    markdown.source_files = 'Sources/Markdown/**/*.swift'
    markdown.dependency 'RichTextView/Core'
    markdown.dependency 'SwiftMarkdownBinary', '0.8.0-patch.1'

    markdown.test_spec 'Tests' do |tests|
      tests.source_files = 'Tests/RichTextViewTests/RichMarkdownParserTests.swift'
    end
  end
end

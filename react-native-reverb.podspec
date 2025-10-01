require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

fabric_enabled = ENV['RCT_NEW_ARCH_ENABLED'] == '1'

Pod::Spec.new do |s|
  s.name         = "react-native-reverb"
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']
  s.homepage     = package['homepage']
  s.author       = package['author']
  s.platform     = :ios, "12.0"
  s.source       = { :git => "https://github.com/azlanali076/react-native-reverb.git", :tag => s.version.to_s }
  
  s.source_files = "ios/**/*.{h,mm}"
  s.dependency 'React-Core'
  s.dependency "React-Codegen"
end
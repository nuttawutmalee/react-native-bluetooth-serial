require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-bluetooth-serial-next"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  react-native-bluetooth-serial-next
                   DESC
  s.homepage     = package["homepage"]
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.authors      = package["author"]
  s.platforms    = { :ios => "9.0" }
  s.source       = { :git => "https://github.com/nuttawutmalee/react-native-bluetooth-serial-next.git", :tag => "#{s.version}" }

  s.dependency "React"

  s.source_files = "ios/**/*.{h,m,swift}"
end


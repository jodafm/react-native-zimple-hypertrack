require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-zimple-hypertrack"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://github.com/jodafm/react-native-zimple-hypertrack"
  # brief license entry:
  s.license      = "MIT"
  # optional - use expanded license entry instead:
  # s.license    = { :type => "MIT", :file => "LICENSE" }
  s.authors      = { "Zimplifica" => "dsanchez@zimplifica.com" }
  s.platforms    = { :ios => "11.0" }
  s.source       = { git: package[:repository][:url] }

  s.source_files = "ios/*.{h,m}"
  s.requires_arc = true

  s.dependency "React"
  s.dependency "HyperTrack/Objective-C", "~> 4.0.1"
end
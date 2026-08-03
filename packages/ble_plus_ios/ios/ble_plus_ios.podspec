Pod::Spec.new do |s|
  s.name             = 'ble_plus_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS implementation of ble_plus BLE plugin.'
  s.description      = <<-DESC
  iOS platform implementation for the ble_plus Flutter plugin,
  providing BLE Central and Peripheral role support via CoreBluetooth.
                       DESC
  s.homepage         = 'https://github.com/your-org/ble_plus'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :http => 'https://github.com/your-org/ble_plus' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.frameworks       = 'CoreBluetooth'
end


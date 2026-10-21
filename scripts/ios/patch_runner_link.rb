#!/usr/bin/env ruby
# Isolated Flutter Runner only; never touches Atlas project.
require 'xcodeproj'

path = ARGV.fetch(0) { abort 'Provide <Runner.xcodeproj> path' }
project = Xcodeproj::Project.open(path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'Runner target missing' unless runner

root = '$(PROJECT_DIR)/NativeRust'
{
  'iphoneos*' => "#{root}/device/libatlas_fsrs7_probe.a",
  'iphonesimulator*' => "#{root}/simulator/libatlas_fsrs7_probe.a"
}.each do |sdk, library|
  path_value = "OTHER_LDFLAGS[sdk=#{sdk}]"
  runner.build_configurations.each do |config|
    existing = config.build_settings[path_value]
    if existing && existing.to_s.include?('atlas_fsrs7_probe.a')
      next
    end
    config.build_settings[path_value] = [
      '$(inherited)',
      '-force_load',
      library,
      # Every symbol is used only via Dart DynamicLibrary.process().
      # Force the linker to retain their public C entry points.
      '-u', '_atlas_fsrs7_engine_version',
      '-u', '_atlas_fsrs7_abi_version',
      '-u', '_atlas_fsrs7_parameter_count',
      '-u', '_atlas_fsrs7_state_size',
      '-u', '_atlas_fsrs7_output_size',
      '-u', '_atlas_fsrs7_next'
    ]
  end
end
project.save
puts 'IOS_ISOLATED_XCODE_NATIVE_LINK_PATCH=PASS'

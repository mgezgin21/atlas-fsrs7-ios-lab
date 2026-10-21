#!/usr/bin/env ruby
# Isolated iOS FFI lab ONLY. Explicit variant selection and resolved-setting checks.
require 'xcodeproj'

path = ARGV.fetch(0) { abort 'Provide <Runner.xcodeproj> path' }
variant = ARGV.fetch(1) { abort 'Provide simulator or device' }
abort 'variant must be simulator or device' unless %w[simulator device].include?(variant)
project_dir = File.dirname(File.expand_path(path))
archive = File.join(project_dir, 'NativeRust', variant, 'libatlas_fsrs7_probe.a')
abort "Native Rust archive missing: #{archive}" unless File.file?(archive) && File.size?(archive)

project = Xcodeproj::Project.open(path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'Runner target missing' unless runner

required_exports = %w[
  atlas_fsrs7_engine_version
  atlas_fsrs7_abi_version
  atlas_fsrs7_parameter_count
  atlas_fsrs7_state_size
  atlas_fsrs7_output_size
  atlas_fsrs7_next
]
# Dart DynamicLibrary.process() does not produce C linker references.
# The old SDK-conditional OTHER_LDFLAGS did not reach Flutter's Runner link step.
# Patch unconditionally per build; CI switches archive before device release.
flags = ['$(inherited)', '-force_load',
         %Q{"$(PROJECT_DIR)/NativeRust/#{variant}/libatlas_fsrs7_probe.a"}]
required_exports.each { |symbol| flags.concat(['-u', "_#{symbol}"]) }
# Match the standalone successful C link probe's framework/library set.
flags.concat(['-framework', 'Foundation', '-framework', 'Security',
              '-framework', 'SystemConfiguration', '-lresolv', '-lc++'])

runner.build_configurations.each do |config|
  config.build_settings.delete('OTHER_LDFLAGS[sdk=iphoneos*]')
  config.build_settings.delete('OTHER_LDFLAGS[sdk=iphonesimulator*]')
  config.build_settings['OTHER_LDFLAGS'] = flags.dup
end
project.save

reloaded = Xcodeproj::Project.open(path)
reloaded_runner = reloaded.targets.find { |target| target.name == 'Runner' }
abort 'Runner missing after save' unless reloaded_runner
reloaded_runner.build_configurations.each do |config|
  effective = Array(config.build_settings.fetch('OTHER_LDFLAGS')).join(' ')
  abort "Runner flags missing for #{config.name}" unless
    effective.include?("NativeRust/#{variant}/libatlas_fsrs7_probe.a") &&
    effective.include?('-force_load') &&
    required_exports.all? { |s| effective.include?("_#{s}") }
end
puts "IOS_RUNNER_ARCHIVE_PATCH=PASS;VARIANT=#{variant};CONFIGURATIONS=#{reloaded_runner.build_configurations.length}"

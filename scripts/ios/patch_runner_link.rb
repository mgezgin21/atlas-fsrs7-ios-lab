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
# DynamicLibrary.process() creates no C reference on its own.
# Explicitly register the Rust archive in Runner's PBXFrameworksBuildPhase.
# Relying only on OTHER_LDFLAGS allowed -u symbols to reach the linker while
# the archive itself was absent from Flutter's actual link invocation.
frameworks = runner.frameworks_build_phase
abort 'Runner lacks Frameworks build phase' unless frameworks
rust_relative_path = "NativeRust/#{variant}/libatlas_fsrs7_probe.a"
# The simulator and device are built sequentially from this same generated app.
# NEVER link both architecture variants in a single Runner binary.
frameworks.files.to_a.each do |build_file|
  previous = build_file.file_ref&.path.to_s
  build_file.remove_from_project if previous.include?('NativeRust/') && previous.end_with?('/libatlas_fsrs7_probe.a')
end
ref = project.files.find { |file| file.path.to_s == rust_relative_path }
ref ||= project.main_group.new_file(rust_relative_path)
ref.last_known_file_type = 'archive.ar'
frameworks.add_file_reference(ref, true)

# -u retains the symbols used only via dlsym(DynamicLibrary.process).
# Keep the normal archive link exactly once via PBXFrameworksBuildPhase,
# instead of forcing a separate copy through -force_load.
flags = ['$(inherited)']
required_exports.each { |symbol| flags.concat(['-u', "_#{symbol}"]) }
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
linked = reloaded_runner.frameworks_build_phase.files.map { |file| file.file_ref&.path.to_s }
abort "Archive not included in Runner's Frameworks phase: #{linked.inspect}" unless linked.include?(rust_relative_path)
abort "Both Rust architectures linked in Runner: #{linked.inspect}" if
  linked.any? { |entry| entry.include?('NativeRust/') && entry != rust_relative_path }
reloaded_runner.build_configurations.each do |config|
  effective = Array(config.build_settings.fetch('OTHER_LDFLAGS')).join(' ')
  abort "Runner export retention flags missing for #{config.name}" unless
    required_exports.all? { |symbol| effective.include?("_#{symbol}") }
end
puts "IOS_RUNNER_NATIVE_ARCHIVE_LINK=PASS;VARIANT=#{variant};CONFIGURATIONS=#{reloaded_runner.build_configurations.length};LINKED_ARCHIVE=#{rust_relative_path}"

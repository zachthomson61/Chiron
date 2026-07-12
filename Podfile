platform :ios, '16.0'

target 'Chiron' do
  use_frameworks!

  pod 'MediaPipeTasksVision'

  # Unit tests import the app module, whose Swift interface references
  # MediaPipeTasksVision — the test target needs the pod search paths (not a
  # second copy of the pods) for its module graph to resolve.
  target 'ChironTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
    # Avoid "Multiple commands produce README.md" by not copying README from pods into the app bundle
    if target.respond_to?(:resources_build_phase) && target.resources_build_phase
      target.resources_build_phase.files.reject! { |f| f.file_ref && f.file_ref.path && f.file_ref.path.end_with?('README.md') }
    end
  end

  # ChironTests is app-hosted (BUNDLE_LOADER = TEST_HOST) and only needs the pod
  # SEARCH PATHS to compile against the app module. The MediaPipe pods inject a
  # -force_load of their static graph library into every integrated target's
  # OTHER_LDFLAGS; loading that archive into BOTH the app and the test bundle
  # duplicates MediaPipe's static calculator registry and crashes the test runner
  # at launch (FunctionRegistry::Register). Strip linker flags from the test
  # aggregate — its symbols resolve through the host app at runtime.
  Dir.glob(File.join(installer.sandbox.root, 'Target Support Files', 'Pods-ChironTests', '*.xcconfig')).each do |path|
    text = File.read(path)
    File.write(path, text.lines.reject { |l| l.start_with?('OTHER_LDFLAGS') }.join)
  end
end

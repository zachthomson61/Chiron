platform :ios, '16.0'

target 'Chiron' do
  use_frameworks!

  pod 'MediaPipeTasksVision'
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
end

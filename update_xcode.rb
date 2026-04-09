require 'xcodeproj'
project_path = 'boringNotch.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'boringNotch' }

# remove file from target
dual_ref = project.files.find { |f| f.path == 'DualLiveActivityView.swift' }
if dual_ref
  target.source_build_phase.remove_file_reference(dual_ref)
  dual_ref.remove_from_project
end

project.save

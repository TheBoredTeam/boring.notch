require 'xcodeproj'

project_path = 'boringNotch.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'boringNotch' }

# Find groups
components_group = project.main_group['boringNotch']['components']
pomodoro_group = components_group['Pomodoro']

# Add file
dual_ref = pomodoro_group['DualLiveActivityView.swift'] || pomodoro_group.new_file('DualLiveActivityView.swift')

# Add to target
unless target.source_build_phase.files_references.include?(dual_ref)
  target.source_build_phase.add_file_reference(dual_ref)
end

project.save

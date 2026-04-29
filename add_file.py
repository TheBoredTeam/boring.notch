#!/usr/bin/env python3
import re

with open('boringNotch.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Add PBXBuildFile entry after PomodoroView.swift in Sources
build_pattern = r'(POMOD0042C5EAFBF00000004 /\* PomodoroView\.swift in Sources \* / = \{isa = PBXBuildFile; fileRef = POMOD0022C5EAFBF00000002 /\* PomodoroView\.swift \* /; \};)'
build_replacement = r'\1\n\t\tPOMODCLOS0001C5EAFBF00000001 /* PomodoroClosedView.swift in Sources */ = {isa = PBXBuildFile; fileRef = POMODCLOS0002C5EAFBF00000001 /* PomodoroClosedView.swift */; };'
content = re.sub(build_pattern, build_replacement, content)

# Add PBXFileReference entry after PomodoroView.swift file reference
file_pattern = r'(POMOD0022C5EAFBF00000002 /\* PomodoroView\.swift \* / = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = PomodoroView\.swift; sourceTree = "<group>"; \};)'
file_replacement = r'\1\n\t\tPOMODCLOS0002C5EAFBF00000001 /* PomodoroClosedView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PomodoroClosedView.swift; sourceTree = "<group>"; };'
content = re.sub(file_pattern, file_replacement, content)

# Add to PBXSourcesBuildPhase
sources_pattern = r'(POMOD0042C5EAFBF00000004 /\* PomodoroView\.swift in Sources \* /,)'
sources_replacement = r'\1\n\t\t\t\tPOMODCLOS0001C5EAFBF00000001 /* PomodoroClosedView.swift in Sources */,'
content = re.sub(sources_pattern, sources_replacement, content)

with open('boringNotch.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Done")
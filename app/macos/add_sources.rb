#!/usr/bin/env ruby
# Adds new Swift source files under Runner/ to the Xcode project's Runner
# group + Runner target's Sources build phase. Idempotent — skips files
# already present. This project doesn't use Xcode's filesystem-synchronized
# groups (objectVersion 54), so files dropped on disk aren't picked up
# automatically; run this after adding any new .swift file to Runner/.
#
# Usage: ruby add_sources.rb file1.swift file2.swift ...
# (paths relative to macos/Runner/)

require "xcodeproj"

project_path = "Runner.xcodeproj"
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == "Runner" }
runner_group = project.main_group["Runner"]

ARGV.each do |filename|
  if runner_group.children.any? { |c| c.display_name == filename }
    puts "skip (already present): #{filename}"
    next
  end
  file_ref = runner_group.new_reference(filename)
  target.add_file_references([file_ref])
  puts "added: #{filename}"
end

project.save

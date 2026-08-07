#!/bin/bash

# This script generates a code context for the given folder structure
# Place this script in the root folder of your project
# Run the command chmod +x get_code_context.sh
# Then run ./get_code_context.sh

# Use the current directory as the project directory
project_dir=$(pwd)

# Output file
output_file="${project_dir}/algo_trading_api-code_context"

# Remove the output file if it already exists
if [ -f "$output_file" ]; then
  rm "$output_file"
fi

# Directories to include
directories=("app" "lib" "config/initializers")

# List of file types and directories to ignore
ignore_files=("*.log" "*.csv" "*.txt" "*.lock" "*.keep" "*.md" "*.yml.enc" "*.key" "*.gitignore" "*.dockerignore")
ignore_directories=(".git" ".github" "log" "tmp" "vendor" "public" "bin" ".kamal" ".ruby-lsp")

# Recursive function to collect files and append their content
read_files() {
  for entry in "$1"/*
  do
    if [ -d "$entry" ]; then
      # Skip ignored directories
      dir_name=$(basename "$entry")
      if [[ ! " ${ignore_directories[@]} " =~ " ${dir_name} " ]]; then
        # Recursively process directories
        read_files "$entry"
      fi
    elif [ -f "$entry" ]; then
      # Check if the file type should be ignored
      should_ignore=false
      for ignore_pattern in "${ignore_files[@]}"; do
        if [[ "$entry" == $ignore_pattern || "$entry" == */$ignore_pattern ]]; then
          should_ignore=true
          break
        fi
      done

      # If the file is not ignored, add its content to the output file
      if ! $should_ignore; then
        relative_path=${entry#"$project_dir/"}
        echo "# File: $relative_path" >> "$output_file"
        cat "$entry" >> "$output_file"
        echo -e "\n" >> "$output_file"
      fi
    fi
  done
}

# Process specified directories
for dir in "${directories[@]}"; do
  if [ -d "${project_dir}/${dir}" ]; then
    read_files "${project_dir}/${dir}"
  fi
done

echo "Code context has been saved to ${output_file}"
